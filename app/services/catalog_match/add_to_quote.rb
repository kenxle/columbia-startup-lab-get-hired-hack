module CatalogMatch
  # Adds an approved catalog item to an RFQ as a new quote line.
  #
  # The line carries the catalog part number, the spec, and the buyer's words
  # as evidence. It has no price yet: the pricing agent fills that in, so the
  # line is held with "unit_price" unresolved and never counts as Ready.
  class AddToQuote
    SPEC_FROM_ITEM = {
      "material" => ->(item) { item["material"] },
      "grade" => ->(item) { [ item["grade"], item["temper"] ].compact.join("-").presence },
      "form" => ->(item) { item["form"] },
      "thickness" => ->(item) { item["thickness_in"] && "#{item['thickness_in']} in#{" (#{item['gauge']} ga)" if item['gauge']}" },
      "width" => ->(item) { (item["width_in"] || item["size_a_in"] || item["diameter_in"] || item["nps"])&.then { |value| "#{value} in" } },
      "length" => ->(item) { item["length_in"] && "#{item['length_in']} in" },
      "standard" => ->(item) { item["standard"] },
      "finish" => ->(item) { item["finish"] }
    }.freeze

    # Reading field -> QuoteLine evidence key.
    EVIDENCE_FROM_READING = {
      "material" => "material", "grade" => "grade", "temper" => "grade", "form" => "form",
      "gauge" => "thickness", "thickness" => "thickness", "width" => "width", "size_a" => "width",
      "diameter" => "width", "nps" => "width", "length" => "length", "standard" => "standard",
      "finish" => "finish", "quantity" => "quantity"
    }.freeze

    def self.call(**arguments) = new(**arguments).call

    def initialize(quote:, item:, match_request:, quantity: nil)
      @quote = quote
      @item = item
      @match_request = match_request
      @quantity = quantity
    end

    def call
      @quote.with_lock do
        line = @quote.quote_lines.build(
          position: (@quote.quote_lines.maximum(:position) || 0) + 1,
          description: @item["description"].to_s.truncate(500),
          original_text: @match_request.description,
          spec: SPEC_FROM_ITEM.transform_values { |value| value.call(@item)&.to_s&.truncate(200) }.compact,
          evidence: evidence,
          quantity: @quantity,
          quantity_unit: @item["unit"],
          catalog_sku: @item["pn"],
          state: "needs_buyer",
          unresolved_fields: [ "unit_price" ],
          notes: "Matched by the catalog agent to #{@item['pn']} for #{@match_request.client.name}; " \
                 "approved by the rep. No price yet: waiting for a benchmark price. " \
                 "#{@item['catalog_provenance'].to_s.capitalize}."
        )
        line.save!
        @quote.invalidate_approval!
        line
      end
    end

    private

    def evidence
      reading = DescriptionReader.read(@match_request.description,
                                       client_terms: ClientMemory.new(@match_request.client).terms)
      reading.fields.each_with_object({}) do |(name, field), result|
        key = EVIDENCE_FROM_READING[name]
        next if key.nil? || result.key?(key) || field["text"].blank?

        result[key] = {
          "text" => field["text"],
          "location" => "client request ##{@match_request.id}",
          "explanation" => field["explanation"].to_s
        }
      end
    end
  end
end
