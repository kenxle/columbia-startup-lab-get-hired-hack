module QuoteWorkspace
  # Builds the approved quote as CSV. Ready lines carry prices; held lines
  # carry no price and include the buyer question. Every text cell is
  # escaped so a spreadsheet never evaluates it as a formula.
  #
  # The csv gem is not a default gem on Ruby 3.4 and is not in the Gemfile,
  # so this writes RFC 4180 output directly, quoting every cell.
  class CsvExport
    class NotApproved < StandardError; end

    FORMULA_PREFIXES = [ "=", "+", "-", "@", "\t", "\r", "\n", "＝", "＋", "－", "＠" ].freeze
    COLUMN_HEADERS = [
      "Line", "Status", "Description", "Material", "Grade", "Form", "Thickness", "Width", "Length",
      "Standard", "Finish", "Part number", "Diameter", "Thread", "Grip", "Drilling",
      "Quantity", "Unit", "Catalog SKU", "Unit price (USD)", "Line total (USD)",
      "Price source", "Benchmark", "Compliance requested", "Question for the buyer",
      "Lead time", "Lead time source"
    ].freeze

    def self.escape_formula(value)
      text = value.to_s
      return text if text.empty?

      starts_with_prefix = FORMULA_PREFIXES.include?(text[0]) || FORMULA_PREFIXES.include?(text.lstrip[0])
      starts_with_prefix ? "'#{text}" : text
    end

    def self.encode_row(cells)
      cells.map { |cell| %("#{cell.to_s.gsub('"', '""')}") }.join(",") + "\r\n"
    end

    def self.format_decimal(value, places)
      rounded = value.round(places)
      integer_part, fraction_part = rounded.to_s("F").split(".")
      "#{integer_part}.#{fraction_part.to_s.ljust(places, '0')[0, places]}"
    end

    def self.format_quantity(value)
      value.to_s("F").sub(/\.0+\z/, "")
    end

    def initialize(quote)
      @quote = quote
    end

    def filename
      "#{@quote.reference}-quote.csv"
    end

    def to_csv
      FinalQuote.new(@quote).with_snapshot do
        rows.map { |cells| self.class.encode_row(cells) }.join
      end
    rescue FinalQuote::NotApproved => error
      raise NotApproved, error.message
    end

    private

    def text(value)
      self.class.escape_formula(value)
    end

    def rows
      lines = @quote.quote_lines.to_a
      output = []
      output << [ "Quote reference", @quote.reference ]
      output << [ "Title", text(@quote.title) ]
      output << [ "Buyer", text(@quote.buyer_name) ]
      output << [ "Approved at", @quote.approved_at.utc.iso8601 ]
      output << []
      output << COLUMN_HEADERS
      lines.each do |line|
        options = QuoteOptions.for(line)
        output << line_row(line, options)
        options.each { |option| output << option_row(line, option) }
      end
      output << []
      output << [ "Subtotal, Ready lines only (USD)", self.class.format_decimal(@quote.subtotal, 2) ]
      has_priced_options = lines.any? { |line| QuoteOptions.for(line).any? { |option| option[:priced] } }
      output << [ "Held lines", has_priced_options ? "Buyer-choice options and held lines are excluded from the subtotal. Choose one option per line; option totals are mutually exclusive." : "#{@quote.held_count} held lines are not priced and are excluded from the subtotal." ]
      output
    end

    def line_row(line, options = [])
      quotable = line.quotable?
      [
        line.position.to_s,
        options.any? { |option| option[:priced] } ? "Buyer choice" : line.status_label,
        text(line.display_description),
        *QuoteLine::SPEC_KEYS.map { |spec_key| text(line.spec_value(spec_key)) },
        line.quantity.nil? ? "" : self.class.format_quantity(line.quantity),
        text(line.quantity_unit),
        quotable ? text(line.catalog_sku) : "",
        quotable ? self.class.format_decimal(line.unit_price, line.unit_price == line.unit_price.round(2) ? 2 : 4) : "",
        quotable ? self.class.format_decimal(line.line_total, 2) : "",
        quotable ? text(line.price_source) : "",
        quotable && !line.rep_entered_price? ? text(benchmark_summary(line)) : "",
        text(compliance_summary(line)),
        quotable ? "" : text(line.clarification_question),
        text(line.display_lead_time),
        line.sourced_lead_time? ? text(line.lead_time_source) : ""
      ]
    end

    def option_row(line, option)
      [
        line.position.to_s, option[:priced] ? "Buyer choice option" : "Held option, unpriced",
        text("#{option[:label]} (choose one; excluded from subtotal). #{option[:spec].map { |key, value| "#{key}: #{value}" }.join('; ')}"),
        *QuoteLine::SPEC_KEYS.map { |key| text(option[:spec][key]) },
        text(option[:quantity]), text(option[:quantity_unit]), text(option[:sku]),
        option[:priced] ? option[:unit_price] : "", option[:priced] ? option[:total] : "",
        option[:priced] ? text(option[:price_source]) : "",
        option[:priced] ? text("#{option[:benchmark]['name']} (as of #{option[:benchmark]['as_of']}; #{option[:benchmark]['kind']})") : "",
        text(compliance_summary(line)), text(line.clarification_question), text(option[:lead_time]), text(option[:lead_time_source])
      ]
    end

    def benchmark_summary(line)
      benchmark = line.benchmark
      return "" unless benchmark.is_a?(Hash) && benchmark["name"].present?

      details = [ benchmark["as_of"].presence && "as of #{benchmark['as_of']}", benchmark["kind"].presence ].compact
      details.any? ? "#{benchmark['name']} (#{details.join(', ')})" : benchmark["name"]
    end

    def compliance_summary(line)
      Array(line.compliance).filter_map { |entry| entry["label"] if entry.is_a?(Hash) }.join("; ")
    end
  end
end
