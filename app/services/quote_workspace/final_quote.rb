module QuoteWorkspace
  # Buyer-facing values are assembled while holding the same lock as edits.
  # Never retain a snapshot across requests or trust a previously loaded approval.
  class FinalQuote
    class NotApproved < StandardError; end

    SAMPLE_NOTICE = "SAMPLE DATA: Synthetic RFQ, catalog items and prices for demonstration.".freeze

    def initialize(quote)
      @quote = quote
    end

    def subject
      with_snapshot { |data| "Quote #{data[:reference]}" }
    end

    def filename
      with_snapshot { |data| "#{data[:basename]}-email-draft.txt" }
    end

    def body(attachments_included: false)
      with_snapshot do |data|
        parts = [ "Draft, not sent", "Concept quote", "Subject: Quote #{data[:reference]}" ]
        parts << SAMPLE_NOTICE if data[:sample]
        parts << "Buyer: #{data[:buyer]}" if data[:buyer].present?
        parts << "Approved quote #{data[:reference]}: #{data[:title]}"
        parts << "Ready-line subtotal: USD #{data[:subtotal]}. Held lines are unpriced and excluded."
        data[:lines].each do |line|
          details = [ "Line #{line[:position]}: #{line[:description]}", "Status: #{line[:status]}",
            "Quantity: #{line[:quantity]}", "Lead time: #{line[:lead_time]}" ]
          if line[:ready]
            details << "Unit price: USD #{line[:unit_price]} | Line total: USD #{line[:total]}"
            details << "Price source: #{line[:price_source]}"
            benchmark = line[:benchmark]
            if line[:rep_price]
              details << "Rep-entered price. Previous benchmark claims do not apply."
            elsif benchmark["name"].present?
              details << "Benchmark: #{benchmark['name']}"
              details << "As of: #{benchmark['as_of']}" if benchmark["as_of"].present?
              details << "Sample benchmark" if benchmark["kind"] == "sample"
              details << benchmark["explanation"] if benchmark["explanation"].present?
            else
              details << "Benchmark: not provided"
            end
          end
          details << "Lead time source: #{line[:lead_time_source]}" if line[:lead_time_source].present?
          details << "Requested paperwork: #{line[:compliance].join('; ')}" if line[:compliance].any?
          details << "Question: #{line[:question]}" unless line[:ready]
          parts << details.join("\n")
        end
        parts << "Paperwork requirements record buyer requests, not certification of stock."
        if attachments_included
          parts << "Attached to this local preview: #{data[:basename]}.pdf and #{data[:basename]}.csv."
          parts << "No email has been sent to the buyer."
        else
          parts << "Files to attach before sending: #{data[:basename]}.pdf and #{data[:basename]}.csv."
          parts << "This is a draft only. Files are not attached and no email has been sent."
        end
        parts.join("\n\n") + "\n"
      end
    end

    def with_snapshot
      @quote.with_lock do
        lines = @quote.quote_lines.reload.to_a
        unless @quote.approved? && @quote.approvable? && @quote.valid? && lines.all?(&:valid?)
          raise NotApproved, "Review and approve the current quote before exporting."
        end

        yield({
          reference: @quote.reference,
          title: @quote.title,
          buyer: @quote.buyer_name,
          approved_at: @quote.approved_at.utc.iso8601,
          sample: @quote.sample_data?,
          basename: "#{@quote.reference}-quote#{@quote.sample_data? ? '-SAMPLE' : ''}",
          subtotal: decimal(lines.select(&:quotable?).sum(BigDecimal("0"), &:line_total), 2),
          lines: lines.map { |line| present_line(line) }
        })
      end
    end

    private

    def decimal(value, places)
      CsvExport.format_decimal(value, places)
    end

    def present_line(line)
      ready = line.quotable?
      benchmark = line.benchmark.is_a?(Hash) ? line.benchmark : {}
      {
        position: line.position,
        description: line.description.presence || "Line #{line.position}",
        spec: QuoteLine::SPEC_KEYS.filter_map do |key|
          value = line.spec_value(key)
          [ key.humanize, value ] if value.present?
        end,
        ready: ready,
        status: ready ? "Ready" : "Held: #{line.status_label}",
        quantity: [ line.quantity && CsvExport.format_quantity(line.quantity), line.quantity_unit ].compact.join(" ").presence || "Not specified",
        sku: ready ? line.catalog_sku : nil,
        unit_price: ready ? decimal(line.unit_price, line.unit_price == line.unit_price.round(2) ? 2 : 4) : nil,
        total: ready ? decimal(line.line_total, 2) : nil,
        price_source: ready ? line.price_source : nil,
        rep_price: ready && line.rep_entered_price?,
        benchmark: ready && !line.rep_entered_price? ? benchmark.slice("name", "as_of", "kind", "explanation") : {},
        compliance: Array(line.compliance).filter_map { |entry| entry["label"].presence if entry.is_a?(Hash) },
        lead_time: line.display_lead_time,
        lead_time_source: line.sourced_lead_time? ? line.lead_time_source : nil,
        question: ready ? nil : line.clarification_question
      }
    end
  end
end
