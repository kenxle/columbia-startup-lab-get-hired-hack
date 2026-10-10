module CatalogMatch
  # The rep approves one or more suggested items for a client: the client's
  # memory learns from it and each item becomes a line on the chosen RFQ.
  class Approve
    class Invalid < StandardError; end

    def self.call(match_request:, part_numbers:, quote:, quantity: nil, catalog: Catalog.default)
      part_numbers = Array(part_numbers).map { |pn| pn.to_s.upcase }.uniq
      raise Invalid, "Choose at least one item to approve." if part_numbers.empty?

      offered = (match_request.suggested_part_numbers + Array(match_request.result["closest"]).map { |entry| entry["pn"] }).map(&:upcase)
      unknown = part_numbers - offered
      raise Invalid, "Only suggested items can be approved (#{unknown.join(', ')} was not suggested)." if unknown.any?

      items = part_numbers.map { |pn| catalog.find(pn) || raise(Invalid, "#{pn} is no longer in the catalog.") }
      quantity = quantity.presence || match_request.quantity

      ActiveRecord::Base.transaction do
        lines = items.map { |item| AddToQuote.call(quote: quote, item: item, match_request: match_request, quantity: quantity) }
        memory = ClientMemory.new(match_request.client)
        learned = items.size == 1 ? memory.learn!(match_request: match_request, item: items.first) : []
        match_request.update!(approved_part_numbers: part_numbers, approved_at: Time.current, quote_id: quote.id)
        { lines: lines, learned: learned }
      end
    end
  end
end
