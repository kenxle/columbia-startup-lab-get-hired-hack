module QuoteWorkspace
  # Presentation of priced alternatives. Nothing here chooses an option or
  # adds it to the quote subtotal. Processing owns the candidate readings.
  class QuoteOptions
    DECIMAL = /\A\d+(?:\.\d+)?\z/
    TEXT_LIMIT = 500

    def self.for(line)
      return [] unless line.state == "needs_buyer" && Array(line.edited_fields).empty?

      options = line.processing.is_a?(Hash) && line.processing["alternates"]
      return [] unless options.is_a?(Array) && options.size.between?(2, 3)

      normalized = options.each_with_index.map { |option, index| normalize(option, index, line) }
      return [] if normalized.any?(&:nil?)
      return [] unless normalized.map { |option| option[:id] }.uniq.size == normalized.size

      normalized
    end

    def self.normalize(option, index, line)
      return unless option.is_a?(Hash)
      return unless %w[id label catalog_sku].all? { |key| text?(option[key]) }
      spec = option["spec"]
      keys = QuoteLine::SPEC_KEYS + %w[thickness_in width_in length_in diameter_in]
      return unless spec.is_a?(Hash) && spec.any? && spec.size <= keys.size
      return unless spec.all? { |key, value| keys.include?(key) && (text?(value) || number(value)) }
      quantity = number(option.fetch("quantity", line.quantity))
      return unless quantity == number(line.quantity) && option.fetch("quantity_unit", line.quantity_unit) == line.quantity_unit
      price = priced_value(option, line, quantity)
      benchmark = price ? option["benchmark"] : {}
      timing = option["lead_time"].is_a?(Hash) ? option["lead_time"] :
        { "text" => option["lead_time"], "source" => option["lead_time_source"] }

      {
        id: option["id"], label: option["label"].match?(/\AOption [A-C]:/) ? option["label"] : "Option #{('A'.ord + index).chr}: #{option['label']}",
        sku: option["catalog_sku"], spec: spec.transform_values(&:to_s), priced: price.present?,
        quantity: quantity ? CsvExport.format_quantity(quantity) : "Not specified", quantity_unit: line.quantity_unit,
        unit_price: price && CsvExport.format_decimal(price, price == price.round(2) ? 2 : 4),
        total: price && CsvExport.format_decimal(quantity * price, 2),
        price_source: price && option["price_source"],
        benchmark: benchmark.slice("name", "as_of", "kind", "unit").merge(
          "explanation" => text?(benchmark["explanation"]) ? benchmark["explanation"] : nil),
        lead_time: text?(timing["text"]) && text?(timing["source"]) ? timing["text"] : "To confirm",
        lead_time_source: text?(timing["source"]) ? timing["source"] : nil
      }
    end

    def self.priced_value(option, line, quantity)
      return unless option.fetch("currency", "USD") == "USD" && quantity && quantity <= 1_000_000_000
      return unless Array(option["unresolved_fields"]).empty? && text?(option["price_source"])
      benchmark = option["benchmark"]
      return unless benchmark.is_a?(Hash) && %w[name as_of kind unit].all? { |key| text?(benchmark[key]) }
      return unless benchmark["unit"] == line.quantity_unit
      return unless benchmark["as_of"].match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(benchmark["as_of"])
      price = number(option["unit_price"])
      price if price && price <= 1_000_000_000 && price == price.round(4)
    rescue Date::Error, ArgumentError
      nil
    end

    def self.number(value)
      return unless value.is_a?(String) || value.is_a?(Numeric)
      raw = value.is_a?(BigDecimal) ? value.to_s("F") : value.to_s
      return unless raw.length <= 40 && raw.match?(DECIMAL)

      value = BigDecimal(raw)
      value if value.finite? && value.positive?
    end

    def self.text?(value)
      value.is_a?(String) && value.strip.present? && value.length <= TEXT_LIMIT
    end

    private_class_method :normalize, :priced_value, :number, :text?
  end
end
