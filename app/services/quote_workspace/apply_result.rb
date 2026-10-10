module QuoteWorkspace
  # Internal integration point for RFQ processing. Validates every row of a
  # processing result, then replaces the quote's lines in one transaction.
  # A rejected result leaves the existing lines and approval untouched.
  #
  # This is not an HTTP endpoint. Callers pass a Ruby hash:
  #   { "schema_version" => 1, "sample_data" => true, "lines" => [ ... ] }
  class ApplyResult
    SCHEMA_VERSION = 1
    LINE_KEYS = %w[
      position description original_text spec quantity quantity_unit catalog_sku
      unit_price price_source state clarification_question notes evidence
      compliance benchmark unresolved_fields
    ].freeze
    TEXT_KEYS = %w[description original_text quantity_unit catalog_sku price_source clarification_question notes].freeze
    DECIMAL_PATTERN = /\A\d+(\.\d+)?\z/

    class InvalidResult < StandardError
      attr_reader :problems

      def initialize(problems)
        @problems = problems
        super("Processing result rejected: #{problems.join('; ')}")
      end
    end

    def self.call(quote:, result:)
      new(quote: quote, result: result).call
    end

    def initialize(quote:, result:)
      @quote = quote
      @result = result
      @problems = []
    end

    def call
      raise InvalidResult.new([ "result must be a hash" ]) unless @result.is_a?(Hash)

      result = @result.deep_stringify_keys
      @problems << "schema_version must be #{SCHEMA_VERSION}" unless result["schema_version"] == SCHEMA_VERSION
      @problems << "sample_data must be true or false" unless [ true, false ].include?(result["sample_data"])

      raw_lines = result["lines"]
      line_attributes = []
      if raw_lines.is_a?(Array) && raw_lines.any?
        line_attributes = raw_lines.each_with_index.map { |raw_line, index| build_line_attributes(raw_line, index) }
        check_unique_positions(line_attributes.compact)
      else
        @problems << "lines must be a non-empty list"
      end
      raise InvalidResult.new(@problems) if @problems.any?

      replace_lines(line_attributes, sample_data: result["sample_data"])
      @quote
    end

    private

    def replace_lines(line_attributes, sample_data:)
      @quote.with_lock do
        @quote.quote_lines.delete_all
        line_attributes.each { |attributes| @quote.quote_lines.create!(attributes) }
        @quote.update_columns(sample_data: sample_data)
        @quote.invalidate_approval!
      end
    rescue ActiveRecord::RecordInvalid => error
      @quote.reload
      raise InvalidResult.new([ "#{error.record.class.name} rejected: #{error.record.errors.full_messages.join(', ')}" ])
    ensure
      @quote.quote_lines.reset
    end

    def build_line_attributes(raw_line, index)
      label = "line #{index + 1}"
      unless raw_line.is_a?(Hash)
        @problems << "#{label} must be a hash"
        return nil
      end

      # Unknown keys are discarded here; only the agreed shape is stored.
      source = raw_line.slice(*LINE_KEYS)
      attributes = {}

      position = source["position"]
      if position.is_a?(Integer) && position.positive?
        attributes["position"] = position
        label = "line at position #{position}"
      else
        @problems << "#{label} needs a positive whole-number position"
      end

      state = source["state"]
      if QuoteLine::STATES.include?(state)
        attributes["state"] = state
      else
        @problems << "#{label} has an unknown state"
      end

      TEXT_KEYS.each do |text_key|
        value = source[text_key]
        if value.nil?
          attributes[text_key] = nil
        elsif value.is_a?(String)
          attributes[text_key] = value.strip.presence
        else
          @problems << "#{label} #{text_key} must be text"
        end
      end

      attributes["quantity"] = parse_decimal(source["quantity"], "quantity", label)
      attributes["unit_price"] = parse_decimal(source["unit_price"], "unit_price", label)
      attributes["spec"] = clean_spec(source["spec"], label)
      attributes["evidence"] = clean_evidence(source["evidence"], label)
      attributes["compliance"] = clean_compliance(source["compliance"], label)
      attributes["benchmark"] = clean_benchmark(source["benchmark"], label)
      attributes["unresolved_fields"] = clean_field_list(source["unresolved_fields"], label)
      attributes["edited_fields"] = []

      check_required_evidence(attributes, label)
      check_state_rules(attributes, label)
      attributes
    end

    def parse_decimal(value, field_name, label)
      return nil if value.nil?

      text = if value.is_a?(BigDecimal)
        value.to_s("F")
      elsif value.is_a?(Numeric)
        value.to_s
      else
        value
      end
      unless text.is_a?(String) && text.strip.match?(DECIMAL_PATTERN)
        @problems << "#{label} #{field_name} must be a nonnegative decimal number"
        return nil
      end
      BigDecimal(text.strip)
    end

    def clean_spec(value, label)
      return {} if value.nil?
      unless value.is_a?(Hash)
        @problems << "#{label} spec must be a hash"
        return {}
      end

      value.slice(*QuoteLine::SPEC_KEYS).each_with_object({}) do |(spec_key, spec_value), cleaned|
        next if spec_value.nil?

        if spec_value.is_a?(String) || spec_value.is_a?(Numeric)
          text = spec_value.to_s.strip
          cleaned[spec_key] = text if text.present?
        else
          @problems << "#{label} spec #{spec_key} must be text"
        end
      end
    end

    def clean_evidence(value, label)
      return {} if value.nil?
      unless value.is_a?(Hash)
        @problems << "#{label} evidence must be a hash"
        return {}
      end

      value.slice(*QuoteLine::EVIDENCE_KEYS).each_with_object({}) do |(evidence_key, entry), cleaned|
        unless entry.is_a?(Hash) && entry["text"].is_a?(String) && entry["text"].strip.present?
          @problems << "#{label} evidence for #{evidence_key} must quote the source text"
          next
        end

        cleaned[evidence_key] = entry.slice(*QuoteLine::EVIDENCE_ENTRY_KEYS).transform_values(&:to_s)
      end
    end

    def clean_compliance(value, label)
      return [] if value.nil?
      unless value.is_a?(Array)
        @problems << "#{label} compliance must be a list"
        return []
      end

      value.filter_map do |entry|
        unless entry.is_a?(Hash) && entry["label"].is_a?(String) && entry["label"].strip.present?
          @problems << "#{label} compliance entries need a label"
          next
        end

        entry.slice(*QuoteLine::COMPLIANCE_ENTRY_KEYS).transform_values(&:to_s)
      end
    end

    def clean_benchmark(value, label)
      return nil if value.nil?
      unless value.is_a?(Hash)
        @problems << "#{label} benchmark must be a hash"
        return nil
      end

      value.slice(*QuoteLine::BENCHMARK_KEYS).transform_values(&:to_s)
    end

    def clean_field_list(value, label)
      return [] if value.nil?
      unless value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) }
        @problems << "#{label} unresolved_fields must be a list of field names"
        return []
      end

      value.map(&:strip).reject(&:empty?).uniq
    end

    # Every spec value and the quantity must trace back to source words.
    def check_required_evidence(attributes, label)
      evidence = attributes["evidence"] || {}
      required_keys = (attributes["spec"] || {}).keys
      required_keys += [ "quantity" ] unless attributes["quantity"].nil?
      missing_keys = required_keys - evidence.keys
      return if missing_keys.empty?

      @problems << "#{label} is missing source evidence for #{missing_keys.join(', ')}"
    end

    # A processing result's ready flag is never trusted on its own.
    def check_state_rules(attributes, label)
      case attributes["state"]
      when "ready"
        quantity = attributes["quantity"]
        @problems << "#{label} is Ready without a positive quantity" unless quantity && quantity.positive?
        @problems << "#{label} is Ready without a catalog SKU" if attributes["catalog_sku"].blank?
        @problems << "#{label} is Ready without a unit price" if attributes["unit_price"].nil?
        @problems << "#{label} is Ready without a price source" if attributes["price_source"].blank?
        @problems << "#{label} is Ready with unresolved fields" if attributes["unresolved_fields"].any?
        benchmark = attributes["benchmark"] || {}
        if benchmark["name"].blank? || benchmark["kind"].blank?
          @problems << "#{label} is Ready without a named benchmark and its kind"
        end
      when "needs_buyer"
        @problems << "#{label} needs the buyer but has no clarification question" if attributes["clarification_question"].blank?
      when "no_match"
        @problems << "#{label} is No match but has no clarification question" if attributes["clarification_question"].blank?
        @problems << "#{label} is No match but names a catalog SKU" if attributes["catalog_sku"].present?
      end

      quantity = attributes["quantity"]
      @problems << "#{label} quantity must be greater than zero" if quantity && !quantity.positive?
    end

    def check_unique_positions(line_attributes)
      positions = line_attributes.filter_map { |attributes| attributes["position"] }
      duplicates = positions.tally.select { |_position, count| count > 1 }.keys
      @problems << "positions must be unique (repeated: #{duplicates.join(', ')})" if duplicates.any?
    end
  end
end
