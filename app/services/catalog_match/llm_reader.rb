require "net/http"
require "json"

module CatalogMatch
  # Reads messy wording with the sponsor LLM (Nicrron gateway, OpenAI-compatible
  # chat completions; model per Hirsh 13:40: anthropic/claude-opus-5).
  #
  # Rules come first. The LLM only fills fields the rules left empty, and a
  # field is accepted only when the LLM quotes words that are actually in the
  # line. No key, or any failure: returns nil and the rules reading stands.
  class LlmReader
    DEFAULT_BASE_URL = "https://api.nicrron.ai/v1".freeze # sponsor gateway (bulletin 13:36, 13:39)
    DEFAULT_MODEL = "anthropic/claude-opus-5".freeze
    TIMEOUT_SECONDS = 25
    RETRY_STATUSES = [ 429, 502, 503, 504 ].freeze

    TEXT_FIELDS = %w[material grade temper form finish standard process quantity_unit].freeze
    NUMBER_FIELDS = %w[thickness width length diameter nps gauge quantity].freeze
    FIELDS = (TEXT_FIELDS + NUMBER_FIELDS + %w[part_number]).freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You read one line of an industrial metals, abrasives or hardware request for quote and return only what its words support.
      Reply with one JSON object and nothing else: {"fields": {...}, "evidence": {...}}.
      "fields" may contain: material (stainless steel, carbon steel, galvanized steel, aluminum, steel shot, steel grit, aluminum oxide, garnet, glass bead, corn cob),
      grade (304, 316L, A36, 6061, 5052, S-330, P1020, 356, A356), temper (T6, T651, H32), form (sheet, plate, flat bar, round bar, square tube, pipe, angle, bolt, screw, nut, washer, ingot, sow, abrasive),
      finish (2B, #4, mill, hot rolled, cold rolled, cadmium plated), standard (A240, A36, A500, A513, A276, A312, B209), process (seamless, welded),
      thickness, width, length, diameter, nps (decimal inches), gauge (integer), quantity (number), quantity_unit (sheet, plate, each, lb, ft, bag), part_number.
      "evidence" maps each field you filled to the exact words from the line it came from.
      Never invent a value. A gauge number is not a thickness: give gauge, leave thickness empty unless a thickness is written.
      "four by eight" on sheet or plate means width 48 and length 96 inches; "4x10" means 48 by 120. Words like "brushed" mean finish #4; "mill finish" means 2B on stainless sheet only if written.
      Leave out any field the line does not settle.
    PROMPT

    # Block Convey / PRISM tracing (Hirsh, 15:05): set a callable in an
    # initializer and it receives {model:, elapsed_ms:, outcome:, request_id:}
    # after every gateway call. Tracing failures never affect the reading.
    class << self
      attr_accessor :trace_listener
    end

    def self.default
      return nil if Rails.env.test? && ENV["CATALOG_MATCH_LLM_IN_TEST"].blank?

      key = ENV["NICRRON_API_KEY"].to_s.strip
      key.empty? ? nil : new(api_key: key)
    end

    def self.enabled? = default.present?

    attr_reader :model

    # transport: a callable (request_body_hash) -> response body String, for tests.
    def initialize(api_key: nil, base_url: ENV.fetch("NICRRON_BASE_URL", DEFAULT_BASE_URL),
                   model: ENV.fetch("NICRRON_MODEL", DEFAULT_MODEL), transport: nil)
      @api_key = api_key
      @base_url = base_url.to_s.chomp("/")
      @model = model
      @transport = transport
    end

    # Returns a `given` hash for DescriptionReader: field => {"value", "text", "explanation", "source"}.
    def read(text)
      text = text.to_s.strip
      return nil if text.empty?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = post(text)
      parsed = body && parse_json(body)
      given = parsed && accept(parsed, text)
      trace(started, body.nil? ? "gateway_error" : (parsed ? "ok" : "unparseable"), body)
      given
    rescue StandardError => error
      Rails.logger.warn("CatalogMatch::LlmReader: #{error.class}: #{error.message}")
      trace(started, "error", nil)
      nil
    end

    def trace(started, outcome, body)
      listener = self.class.trace_listener
      return unless listener && started

      request_id = body && (JSON.parse(body)["id"] rescue nil)
      listener.call(model: @model, elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
                    outcome: outcome, request_id: request_id)
    rescue StandardError => error
      Rails.logger.warn("CatalogMatch::LlmReader trace: #{error.class}: #{error.message}")
    end

    private

    def post(text)
      request = {
        "model" => @model,
        "max_tokens" => 600,
        "messages" => [
          { "role" => "system", "content" => SYSTEM_PROMPT },
          { "role" => "user", "content" => text }
        ]
      }
      return @transport.call(request) if @transport

      uri = URI("#{@base_url}/chat/completions")
      2.times do |attempt|
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = TIMEOUT_SECONDS
        http_request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json", "Authorization" => "Bearer #{@api_key}")
        http_request.body = JSON.generate(request)
        response = http.request(http_request)
        return response.body if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn("CatalogMatch::LlmReader: HTTP #{response.code} from the gateway (attempt #{attempt + 1})")
        return nil unless RETRY_STATUSES.include?(response.code.to_i)
      end
      nil
    end

    def parse_json(body)
      envelope = JSON.parse(body)
      content = envelope.dig("choices", 0, "message", "content").to_s
      return nil unless requested_model?(envelope["model"])

      json = content[/\{.*\}/m]
      json && JSON.parse(json)
    rescue JSON::ParserError
      nil
    end

    def requested_model?(actual)
      return false unless actual.is_a?(String) && actual.present?

      expected = @model.to_s.strip.downcase.split("/").last.to_s
      received = actual.strip.downcase.split("/").last.to_s
      expected.present? && (received == expected || received.match?(/\A#{Regexp.escape(expected)}[-@]\d{8}\z/))
    end

    # Keep a field only when its evidence is really in the line.
    def accept(parsed, text)
      fields = parsed["fields"].is_a?(Hash) ? parsed["fields"] : {}
      evidence = parsed["evidence"].is_a?(Hash) ? parsed["evidence"] : {}
      normalized_text = squash(text)
      fields.each_with_object({}) do |(name, value), given|
        next unless FIELDS.include?(name) && value.present?

        quote = evidence[name].to_s.strip
        next if quote.empty? || !normalized_text.include?(squash(quote))

        given[name] = {
          "value" => value,
          "text" => quote,
          "explanation" => "read by #{@model.split('/').last} from \"#{quote}\"",
          "source" => "llm"
        }
      end
    end

    def squash(value)
      value.to_s.downcase.gsub(/[^a-z0-9#\/.\-]+/, " ").squish
    end
  end
end
