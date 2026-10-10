# frozen_string_literal: true

require "json"

module RfqProcessing
  # Claude reads one RFQ line into the same field names the rules use. The
  # rules keep the last word on anything they computed (unit conversion, gauge
  # lookup, dimension parsing); Claude only fills what the rules left empty,
  # and every value it adds must quote words that are actually in the line.
  #
  # The anthropic gem is required lazily in build_client, so this file loads
  # without it and the specs run against a stub client.
  class LlmParser
    MODEL = "claude-opus-5-5"
    MAX_TOKENS = 2048
    HIGH_CONFIDENCE = 0.9    # Claude must be at least this sure before a disagreement is recorded
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
    def self.from_env(client: nil)
      return new(client: client) if client

      api_key = presence(ENV.fetch("ANTHROPIC_API_KEY", nil))
      auth_token = presence(ENV.fetch("ANTHROPIC_AUTH_TOKEN", nil))
      return nil if api_key.nil? && auth_token.nil?

      new(client: build_client(api_key: api_key, auth_token: auth_token))
    end

    def self.build_client(api_key:, auth_token:)
      require "anthropic"
      Anthropic::Client.new(api_key: api_key, auth_token: auth_token)
    end

    def self.presence(value)
      value = value.to_s.strip
      value.empty? ? nil : value
    end
    private_class_method :build_client, :presence

    def initialize(client:, model: MODEL)
      @client = client
      @model = model
    end

    # One Claude call. A Hash with string keys: "fields", "evidence", "unclear".
    # Never raises on API errors: warns and returns nil.
    def read(text)
      response = @client.messages.create(
        model: @model,
        max_tokens: MAX_TOKENS,
        system_: SYSTEM_PROMPT,
        messages: [{ role: "user", content: text.to_s }],
        output_config: { format: { type: "json_schema", schema: SCHEMA } }
      )
      block = Array(response.content).find { |b| b.type.to_s == "text" }
      if block.nil?
        warn "LlmParser: Claude returned no text block"
        return nil
      end
      normalize(JSON.parse(block.text))
    rescue StandardError => e
      warn "LlmParser: Claude read failed (#{e.class}: #{e.message})"
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

      claude["fields"].each do |field, value|
        next if value.nil?

        quote = claude["evidence"].find { |e| e["field"] == field }
        next if quote.nil? || !quoted?(quote["text"], line) # no source words in the line: not used

        current = reading.fields[field]
        if current.nil?
          fill(reading, field, value, quote)
        elsif quote["confidence"] >= HIGH_CONFIDENCE && differs?(current, value)
          reading.conflicts << { "code" => "llm_disagrees",
                                 "message" => "Claude read #{field} as #{value} from \"#{quote['text']}\"; the rules read #{current}. The rules' value is kept.",
                                 "fields" => [field] }
        end
      end
      reading
    end

    private

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
      !words.empty? && line.gsub(/\s+/, " ").downcase.include?(words.downcase)
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
      parsed = {} unless parsed.is_a?(Hash)
      fields = parsed["fields"].is_a?(Hash) ? parsed["fields"] : {}
      evidence = parsed["evidence"].is_a?(Array) ? parsed["evidence"].select { |e| e.is_a?(Hash) } : []
      unclear = parsed["unclear"].is_a?(Array) ? parsed["unclear"] : []
      {
        "fields" => FIELDS.to_h { |field| [field, coerce(field, fields[field])] },
        "evidence" => evidence.map do |e|
          { "field" => e["field"].to_s, "text" => e["text"].to_s, "note" => e["note"].to_s, "confidence" => e["confidence"].to_f }
        end,
        "unclear" => unclear.map(&:to_s)
      }
    end

    def coerce(field, value)
      return nil if value.nil?

      if NUMBER_FIELDS.include?(field)
        number = value.is_a?(Numeric) ? value : Float(value.to_s, exception: false)
        number && Units.tidy(number)
      else
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
