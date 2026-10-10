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
      compliance benchmark unresolved_fields line_id processing lead_time lead_time_source
    ].freeze
    TEXT_KEYS = %w[description original_text quantity_unit catalog_sku price_source clarification_question notes lead_time lead_time_source].freeze
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

      check_processing_metadata
      raise InvalidResult.new(@problems) if @problems.any?

      result = @result.deep_stringify_keys
      unless Quote.valid_processing_metadata?(result["revision"], revision: true)
        @problems << "revision must be bounded JSON with a nonblank revision id"
      end
      @problems << "schema_version must be #{SCHEMA_VERSION}" unless result["schema_version"] == SCHEMA_VERSION
      @problems << "sample_data must be true or false" unless [ true, false ].include?(result["sample_data"])

      raw_lines = result["lines"]
      line_attributes = []
      if raw_lines.is_a?(Array) && raw_lines.any?
        line_attributes = raw_lines.each_with_index.map { |raw_line, index| build_line_attributes(raw_line, index) }
        check_unique_positions(line_attributes.compact)
        line_ids = line_attributes.compact.filter_map { |attributes| attributes["line_id"] }
        @problems << "line_id must be unique within a quote" unless line_ids.uniq.length == line_ids.length
      else
        @problems << "lines must be a non-empty list"
      end
      raise InvalidResult.new(@problems) if @problems.any?

      replace_lines(line_attributes, sample_data: result["sample_data"], processing_revision: result["revision"], processing_evidence: @processing_evidence)
      @quote
    end

    private

    def check_processing_metadata
      if @result.keys.map(&:to_s).uniq.length != @result.keys.length
        @problems << "result keys must be unique after converting to text"
        return
      end
      source = @result.key?("source") ? @result["source"] : @result[:source]
      warnings = @result.key?("warnings") ? @result["warnings"] : @result[:warnings]
      begin
        @processing_evidence = Quote.normalized_processing_evidence(source: source, warnings: warnings)
      rescue Quote::InvalidProcessingEvidence => error
        @problems.concat(error.problems)
      end
      revision = @result.key?("revision") ? @result["revision"] : @result[:revision]
      unless Quote.valid_processing_metadata?(revision, revision: true)
        @problems << "revision must be bounded JSON with a nonblank revision id"
      end
      raw_lines = @result["lines"] || @result[:lines]
      return unless raw_lines.is_a?(Array)

      raw_lines.each_with_index do |line, index|
        next unless line.is_a?(Hash)

        if line.keys.map(&:to_s).uniq.length != line.keys.length
          @problems << "line #{index + 1} keys must be unique after converting to text"
          next
        end

        processing = line.key?("processing") ? line["processing"] : line[:processing]
        identifier = line.key?("line_id") ? line["line_id"] : line[:line_id]
        unless Quote.valid_processing_metadata?(processing)
          @problems << "line #{index + 1} processing must be bounded JSON"
        end
        unless identifier.nil? || Quote.valid_processing_identifier?(identifier)
          @problems << "line #{index + 1} line_id must be nonblank text of 200 characters or fewer"
        end
      end
    end

    def replace_lines(line_attributes, sample_data:, processing_revision:, processing_evidence:)
      @quote.with_lock do
        @quote.quote_lines.delete_all
        line_attributes.each { |attributes| @quote.quote_lines.create!(attributes) }
        @quote.update_columns({ sample_data: sample_data, processing_revision: processing_revision }.merge(processing_evidence))
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
      attributes["line_id"] = source["line_id"]
      attributes["processing"] = source["processing"]
      bridge_processing_lead_time(source, attributes, label)

      check_required_evidence(attributes, label)
      check_state_rules(attributes, label)
      attributes
    end

    # Nested timing is a stock-based promise. Explicit schema-1 timing fields,
    # including explicit nulls, retain precedence for backward compatibility.
    def bridge_processing_lead_time(source, attributes, label)
      processing = source["processing"]
      return unless processing.is_a?(Hash) && processing.key?("lead_time")
      return if processing["lead_time"].nil?

      timing = processing["lead_time"]
      unless timing.is_a?(Hash) && (timing.keys - %w[text stocked source]).empty? &&
          [ true, false ].include?(timing["stocked"]) &&
          %w[text source].all? { |key| timing[key].is_a?(String) && timing[key].strip.present? && timing[key].length <= 200 }
        @problems << "#{label} processing lead_time must contain stocked boolean and bounded text and source"
        return
      end
      return if source.key?("lead_time") || source.key?("lead_time_source")
      return unless timing["stocked"] && attributes["state"] == "ready"
      return if timing["text"].strip.casecmp?("to confirm")

      candidates = processing.dig("match", "candidates") if processing["match"].is_a?(Hash)
      candidate = Array(candidates).find do |entry|
        entry.is_a?(Hash) && [ entry["item_id"], entry["part_number"] ].compact.include?(attributes["catalog_sku"])
      end
      stock = candidate && candidate["stock"].is_a?(Hash) ? candidate["stock"] : {}
      return if stock["stock_reported"] == false || stock["in_stock"] == false

      provenance = [ timing["source"], stock["stock_scope"], stock["catalog_provenance"], candidate&.[]("catalog") ].compact.join(" ")
      # Third-party or constructed stock cannot establish RudCo inventory.
      return if provenance.match?(/\b(?:third[ -]party|dealer|supplier|retailer|distributor|sample|synthetic|unknown|unconfirmed)\b|\bno stock\b|\bnot (?:in stock|stocked|RudCo inventory)\b/i)

      attributes["lead_time"] = timing["text"].strip
      attributes["lead_time_source"] = timing["source"].strip
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
