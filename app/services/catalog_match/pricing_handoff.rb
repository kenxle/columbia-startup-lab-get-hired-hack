module CatalogMatch
  # The seam between the matcher and the pricing agent
  # (DistributorPricing::Engine#price_line, built by Tisch with Codex).
  #
  # Matching decides which catalog item a line is; pricing prices that item.
  # request_for(line) gives the pricing engine the approved item, quantity and
  # unit. apply(line:, result:) writes the engine's answer back, and trusts
  # nothing: a line becomes Ready only when the result is "ready" with a
  # positive price, a currency and an expiry still in the future.
  class PricingHandoff
    class Invalid < StandardError; end

    PRICE_STATUSES = %w[ready needs_buyer needs_procurement not_competitive].freeze

    def self.request_for(line, catalog: Catalog.default)
      item = catalog.find(line.catalog_sku)
      raise Invalid, "Line #{line.position} has no catalog item to price." unless item

      {
        "item" => item.merge("part_number" => item["pn"], "item_id" => item["item_id"] || item["pn"]),
        "quantity" => line.quantity&.to_s("F")&.sub(/\.0\z/, ""),
        "unit" => line.quantity_unit,
        "requirements" => { "certifications" => Array(line.compliance).filter_map { |entry| entry["label"] } }
      }
    end

    def self.apply(line:, result:, now: Time.current)
      new(line, result.to_h.deep_stringify_keys, now).apply
    end

    def initialize(line, result, now)
      @line = line
      @result = result
      @now = now
    end

    def apply
      status = @result["status"]
      raise Invalid, "Unknown pricing status #{status.inspect}." unless PRICE_STATUSES.include?(status)
      if @result["part_number"].present? && !@result["part_number"].casecmp?(@line.catalog_sku.to_s)
        raise Invalid, "Pricing was for #{@result['part_number']}, but the line is #{@line.catalog_sku}."
      end

      @line.quote.with_lock do
        @line.reload
        priced? ? write_price : write_hold(status)
        @line.save!
        @line.quote.invalidate_approval!
      end
      @line
    end

    private

    def priced?
      return false unless @result["status"] == "ready"

      price = BigDecimal(@result["unit_price"].to_s, exception: false)
      expiry = Time.zone.parse(@result["quote_valid_until"].to_s) rescue nil
      price&.positive? && @result["currency"].present? && expiry && expiry > @now
    end

    def write_price
      analysis = @result["pricing_analysis"] || {}
      offer = @result["selected_offer"] || {}
      @line.unit_price = BigDecimal(@result["unit_price"].to_s)
      @line.price_source = "Pricing agent: #{offer['supplier'] || offer['id'] || 'supplier offer'} landed cost, " \
                           "#{@result['currency']}, #{@result['price_scope'] || 'delivered ex tax'}".first(200)
      @line.benchmark = {
        "name" => "Median of #{analysis['independent_benchmark_suppliers']} independent delivered supplier quotes",
        "as_of" => @result["calculated_at"],
        "unit" => "#{@result['currency']} per #{@line.quantity_unit || 'unit'}",
        "kind" => "market",
        "explanation" => [ analysis["comparison_basis"],
                           ("Market low #{analysis['market_low_unit_price']}, median #{analysis['market_median_unit_price']}, " \
                            "high #{analysis['market_high_unit_price']}." if analysis["market_median_unit_price"]),
                           "Valid until #{@result['quote_valid_until']}." ].compact.join(" ")
      }
      @line.unresolved_fields = Array(@line.unresolved_fields) - [ "unit_price" ]
      @line.state = Array(@line.unresolved_fields).empty? ? "ready" : "needs_buyer"
    end

    def write_hold(status)
      @line.unit_price = nil
      @line.price_source = nil
      @line.unresolved_fields = Array(@line.unresolved_fields) | [ "unit_price" ]
      @line.state = "needs_buyer"
      reasons = Array(@result["reasons"]).first(5)
      label = { "needs_buyer" => "needs the buyer", "needs_procurement" => "needs supplier evidence",
                "not_competitive" => "not competitive at the minimum margin", "ready" => "result incomplete" }.fetch(status)
      note = "Pricing #{label}: #{reasons.join(' ')}".strip
      @line.notes = [ @line.notes.to_s.sub(/\n?Pricing [^\n]*\z/, ""), note ].compact_blank.join("\n").first(2_000)
      question = Array(@result["buyer_questions"]).first
      @line.clarification_question = question.first(1_000) if status == "needs_buyer" && question.present?
    end
  end
end
