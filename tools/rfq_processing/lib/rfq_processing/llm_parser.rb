# frozen_string_literal: true

require "json"
require_relative "openai_compatible_client"

module RfqProcessing
  # Claude reads one RFQ line into the same field names the rules use. The
  # rules keep the last word on anything they computed (unit conversion, gauge
  # lookup, dimension parsing); Claude only fills what the rules left empty,
  # and every value it adds must quote words that are actually in the line.
  #
  # Two ways to reach Claude Opus 5, both decided by the team on 2026-10-10:
  # the Nicrron gateway (OpenAI-compatible chat completions, OpenAiCompatibleClient)
  # or the Anthropic API through the anthropic gem. The gem is required lazily in
  # build_client, so this file loads without it and the specs run against stubs.
  # A response that names a different model than the one asked for is dropped,
  # never used: no silent model substitution.
  class LlmParser
    ANTHROPIC_MODEL = "claude-opus-5"
    MODEL = ANTHROPIC_MODEL
    NICRRON_MODEL = "anthropic/claude-opus-5"
    NICRRON_BASE_URL = "https://api.nicrron.ai/v1"
    PROVIDERS = %w[anthropic nicrron].freeze
    MAX_TOKENS = 2048
    HIGH_CONFIDENCE = 0.9    # minimum confidence for a fill or a disagreement
    NUMERIC_TOLERANCE = 0.01 # numbers within 1% of the rules' value are the same number

    NUMBER_FIELDS = %w[thickness_in wall_in width_in length_in diameter_in quantity].freeze
    FIELDS = %w[material grade temper form thickness_in wall_in width_in length_in diameter_in
                quantity quantity_unit standard finish coating part_number].freeze

    # Structured output schema. Every object has additionalProperties false and
    # a required list; nullable values use anyOf, which the API supports.
    SCHEMA = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => %w[fields evidence unclear],
      "properties" => {
        "fields" => {
          "type" => "object",
          "additionalProperties" => false,
          "required" => FIELDS,
          "properties" => FIELDS.to_h { |field|
            [field, { "anyOf" => [{ "type" => NUMBER_FIELDS.include?(field) ? "number" : "string" }, { "type" => "null" }] }]
          }
        },
        "evidence" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => %w[field text note confidence],
            "properties" => {
              "field" => { "type" => "string" },
              "text" => { "type" => "string" },
              "note" => { "type" => "string" },
              "confidence" => { "type" => "number" }
            }
          }
        },
        "unclear" => { "type" => "array", "items" => { "type" => "string" } }
      }
    }.freeze

    SYSTEM_PROMPT = <<~PROMPT
      You read one line of an industrial metals or hardware RFQ and return the fields its words support.
      Return only what the words support. Never invent a value. A field the line does not settle stays null.
      For every field you fill, add one evidence entry that quotes the exact source words from the line, with a short note and a confidence from 0 to 1.
      All dimensions are decimal inches.
      A gauge number is not a thickness. When only a gauge is written, leave thickness_in null and put the gauge in a note.
      Do not guess the material from a grade alone unless the grade is unambiguous: 304 and 316 are stainless steel; 6061 and 5052 are aluminum; A36 is carbon steel.
      Name materials plainly: stainless steel, carbon steel, aluminum, galvanized steel. Name forms plainly: sheet, plate, flat bar, round bar, square tube, rectangular tube, round tube, pipe, angle, channel.
      Put anything you cannot settle in "unclear".
    PROMPT

    # nil when no credentials are configured, so the pipeline skips the step.
    # A client passed in is used as is (for tests, or a client built elsewhere).
    #
    # Environment: NICRRON_API_KEY picks the Nicrron gateway (NICRRON_BASE_URL and
    # NICRRON_MODEL override the defaults); otherwise ANTHROPIC_API_KEY or
    # ANTHROPIC_AUTH_TOKEN picks the Anthropic API (ANTHROPIC_MODEL overrides the
    # model). With both keys, Nicrron wins unless RFQ_LLM_PROVIDER names one. A
    # forced provider without its key, or an unknown name, turns the step off with
    # a warning rather than quietly using the other one.
    def self.from_env(client: nil)
      return new(client: client) if client

      nicrron_key = presence(ENV.fetch("NICRRON_API_KEY", nil))
      api_key = presence(ENV.fetch("ANTHROPIC_API_KEY", nil))
      auth_token = presence(ENV.fetch("ANTHROPIC_AUTH_TOKEN", nil))
      available = []
      available << "nicrron" if nicrron_key
      available << "anthropic" if api_key || auth_token

      case choose_provider(available)
      when "nicrron"
        model = presence(ENV.fetch("NICRRON_MODEL", nil)) || NICRRON_MODEL
        base_url = presence(ENV.fetch("NICRRON_BASE_URL", nil)) || NICRRON_BASE_URL
        new(client: OpenAiCompatibleClient.new(api_key: nicrron_key, base_url: base_url, model: model), model: model)
      when "anthropic"
        model = presence(ENV.fetch("ANTHROPIC_MODEL", nil)) || ANTHROPIC_MODEL
        new(client: build_client(api_key: api_key, auth_token: auth_token), model: model)
      end
    end

    def self.choose_provider(available)
      forced = presence(ENV.fetch("RFQ_LLM_PROVIDER", nil))&.downcase
      return available.first if forced.nil?
      return forced if available.include?(forced)

      if PROVIDERS.include?(forced)
        warn "LlmParser: configured provider key is not set; the Claude step is off"
      else
        warn "LlmParser: unsupported provider configuration; the Claude step is off"
      end
      nil
    end

    def self.build_client(api_key:, auth_token:)
      require "anthropic"
      Anthropic::Client.new(api_key: api_key, auth_token: auth_token)
    end

    def self.presence(value)
      value = value.to_s.strip
      value.empty? ? nil : value
    end
    private_class_method :choose_provider, :build_client, :presence

    # No silent model substitution. True when the answered name is the asked one, or the asked
    # one with a dated snapshot suffix, after lowercasing both and removing a "provider/" prefix.
    # "claude-opus-5-5" is not "claude-opus-5". Shared with bin/llm-smoke --models.
    def self.same_model?(asked, answered)
      asked = bare_model_name(asked)
      got = bare_model_name(answered)
      got == asked || got.match?(/\A#{Regexp.escape(asked)}[-@]\d{8}\z/)
    end

    def self.bare_model_name(name)
      name.to_s.strip.downcase.sub(%r{\A[^/]+/}, "")
    end

    attr_reader :client, :provider, :model

    # A client that responds to chat is an OpenAI-compatible gateway client (provider
    # "nicrron"); anything else is treated as the Anthropic SDK client. The model
    # defaults to the gateway client's own model, or to the Opus 5 id for each provider.
    def initialize(client:, model: nil)
      @client = client
      @provider = client.respond_to?(:chat) ? "nicrron" : "anthropic"
      @model = (model || default_model).to_s
    end

    # Goes into the result hash as revision.llm. Keep these two keys.
    def describe
      { "provider" => @provider, "model" => @model }
    end

    # One Claude call. A Hash with string keys: "fields", "evidence", "unclear".
    # Never raises on API errors: warns and returns nil.
    def read(text)
      parsed = @provider == "nicrron" ? read_through_gateway(text) : read_through_anthropic(text)
      parsed.nil? ? nil : normalize(parsed)
    rescue StandardError => e
      warn "LlmParser: Claude read failed (#{e.class})"
      nil
    end

    # Merges a Claude reading into the rules' Reading and returns that same Reading.
    # Empty fields take Claude's value; fields the rules set are never overwritten.
    def refine(reading, text)
      claude = read(text)
      return reading if claude.nil?

      reading.fields ||= {}
      reading.evidence ||= {}
      reading.confidence ||= {}
      reading.rules_used ||= []
      reading.conflicts ||= []
      reading.unknowns ||= []
      line = text.to_s
      used = false

      claude["fields"].each do |field, value|
        next if value.nil?

        quote = claude["evidence"].find { |e| e["field"] == field }
        next if quote.nil? || !quoted?(quote["text"], line) # no source words in the line: not used
        next unless quote["confidence"].finite? && (HIGH_CONFIDENCE..1.0).cover?(quote["confidence"])

        current = reading.fields[field]
        if current.nil?
          fill(reading, field, value, quote)
          used = true
        elsif differs?(current, value)
          reading.conflicts << { "code" => "llm_disagrees",
                                 "message" => "Claude read #{field} as #{value} from \"#{quote['text']}\"; the rules read #{current}. The rules' value is kept.",
                                 "fields" => [field] }
          used = true
        end
      end
      # Do not let fields filled by Claude make a line Ready while that same
      # response declares uncertainty. Existing rules holds already cover this.
      if claude["unclear"].any? { |note| !note.strip.empty? } && reading.conflicts.empty? && reading.unknowns.empty?
        reading.conflicts << { "code" => "llm_unclear", "fields" => [],
                               "message" => "Claude could not settle this line. Please confirm its reading." }
        used = true
      end
      reading.rules_used << "Claude model: #{@model}" if used
      reading
    end

    private

    def default_model
      return ANTHROPIC_MODEL unless @provider == "nicrron"

      name = @client.respond_to?(:model) ? @client.model.to_s.strip : ""
      name.empty? ? NICRRON_MODEL : name
    end

    def read_through_anthropic(text)
      response = @client.messages.create(
        model: @model,
        max_tokens: MAX_TOKENS,
        system_: SYSTEM_PROMPT,
        messages: [{ role: "user", content: text.to_s }],
        output_config: { format: { type: "json_schema", schema: SCHEMA } }
      )
      return nil unless same_model?(response.respond_to?(:model) ? response.model : nil)

      block = Array(response.content).find { |b| b.type.to_s == "text" }
      if block.nil?
        warn "LlmParser: Claude returned no text block"
        return nil
      end
      JSON.parse(block.text)
    end

    def read_through_gateway(text)
      reply = @client.chat(system: SYSTEM_PROMPT, user: text.to_s, schema: SCHEMA, max_tokens: MAX_TOKENS)
      return nil if reply.nil? # the client already said why
      return nil unless same_model?(reply["model"])

      JSON.parse(strip_fences(reply["text"]))
    rescue JSON::ParserError => e
      warn "LlmParser: the gateway's reply is not JSON (#{e.class})"
      nil
    end

    # "```json\n{...}\n```" or "```\n{...}\n```" to "{...}"; anything else is returned trimmed.
    def strip_fences(content)
      text = content.to_s.strip
      fenced = /\A```[A-Za-z0-9_-]*[ \t]*\r?\n?(.*?)\r?\n?[ \t]*```\z/m.match(text)
      (fenced ? fenced[1] : text).strip
    end

    # The answer's model name must pass LlmParser.same_model?; a reading from another model is
    # dropped with a warning. A missing name cannot establish model identity.
    def same_model?(answered)
      answered = answered.to_s.strip
      return true if !answered.empty? && self.class.same_model?(@model, answered)

      warn "LlmParser: #{answered.empty? ? 'no model identity' : 'model identity mismatch'}; reading dropped"
      false
    end

    def fill(reading, field, value, quote)
      reading.fields[field] = value
      reading.evidence[field] = { "text" => quote["text"], "location" => reading.location,
                                  "explanation" => "read by Claude: #{quote['note']}" }
      reading.confidence[field] = quote["confidence"]
      reading.rules_used << "Claude read: #{field}"
      reading.unknowns.reject! { |u| u["field"] == field }
    end

    # Claude's quoted words must be in the line, case-insensitively; whitespace runs are collapsed.
    def quoted?(words, line)
      words = words.to_s.strip.gsub(/\s+/, " ")
      return false if words.empty?

      lead = words.match?(/\A[[:alnum:]]/) ? "(?<![[:alnum:]])" : ""
      trail = words.match?(/[[:alnum:]]\z/) ? "(?![[:alnum:]])" : ""
      Regexp.new("#{lead}#{Regexp.escape(words)}#{trail}", Regexp::IGNORECASE).match?(line.gsub(/\s+/, " "))
    end

    def differs?(current, value)
      if current.is_a?(Numeric) && value.is_a?(Numeric)
        base = current.abs
        return !value.zero? if base.zero?

        (current - value).abs.fdiv(base) > NUMERIC_TOLERANCE # fdiv: both sides may be Integers
      else
        !current.to_s.strip.casecmp?(value.to_s.strip)
      end
    end

    # The parsed JSON in the schema's shape, with only known fields and typed values.
    def normalize(parsed)
      unless reading_shape?(parsed)
        warn "LlmParser: malformed reading shape; reading dropped"
        return nil
      end

      fields = parsed["fields"]
      evidence = parsed["evidence"]
      unclear = parsed["unclear"]
      {
        "fields" => FIELDS.to_h { |field| [field, coerce(field, fields[field])] },
        "evidence" => evidence.map do |e|
          { "field" => e["field"].to_s, "text" => e["text"].to_s, "note" => e["note"].to_s, "confidence" => e["confidence"].to_f }
        end,
        "unclear" => unclear.map(&:to_s)
      }
    end

    # Missing field values may be normalized to nil, but malformed containers
    # must never masquerade as a successful, empty provider reading.
    def reading_shape?(parsed)
      return false unless parsed.is_a?(Hash) && parsed["fields"].is_a?(Hash) &&
                          parsed["evidence"].is_a?(Array) && parsed["unclear"].is_a?(Array)
      return false unless parsed["fields"].values.all? { |value| value.nil? || value.is_a?(String) || value.is_a?(Numeric) }
      return false unless parsed["unclear"].all? { |note| note.is_a?(String) }

      parsed["evidence"].all? do |entry|
        entry.is_a?(Hash) && %w[field text note].all? { |key| entry[key].is_a?(String) } &&
          (entry["confidence"].is_a?(Numeric) || entry["confidence"].is_a?(String))
      end
    end

    def coerce(field, value)
      return nil if value.nil?

      if NUMBER_FIELDS.include?(field)
        number = value.is_a?(Numeric) ? value : Float(value.to_s, exception: false)
        return nil unless number && number.finite? && number.positive?

        rounded = Units.tidy(number)
        rounded.positive? ? rounded : nil
      else
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
