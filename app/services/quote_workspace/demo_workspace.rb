require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

module QuoteWorkspace
  # Development-only sample records, separate from the fixed Demo fixture.
  # Existing RFQs are never replaced. Explicit populate! can top up an older
  # local workspace; automatic first-visit seeding only touches an empty one.
  class DemoWorkspace
    SIZE = 3
    REQUESTS = [
      { title: "Steel shot replenishment", buyer_name: "Hudson Surface Prep",
        source_text: "S-330 steel shot, 100 lb" },
      { title: "Structural plate order", buyer_name: "Harbor Fabrication",
        source_text: "A36 plate 1/4 x 48 x 96, qty 5" }
    ].freeze

    def self.seed_if_empty!(workspace_token:)
      return [] unless Rails.env.development?
      return [] if Quote.for_workspace(workspace_token).exists?

      populate!(workspace_token: workspace_token)
    end

    def self.populate!(workspace_token:)
      return [] unless Rails.env.development?
      raise ArgumentError, "A workspace token is required" if workspace_token.blank?

      Quote.transaction do
        count = Quote.for_workspace(workspace_token).count
        return [] if count >= SIZE

        created = []
        unless Quote.for_workspace(workspace_token).exists?(buyer_name: Demo::BUYER_NAME, source_text: Demo::SOURCE_TEXT)
          quote = Demo.create!(workspace_token: workspace_token)
          created << quote
          count += 1
        end
        catalog = CatalogMatch::Catalog.new(%w[rudco metals])
        matcher = ProcessRfq::IntakeMatcher.new(client: nil, catalog: catalog, service: CatalogMatch::Matcher)
        existing = Quote.for_workspace(workspace_token).pluck(:buyer_name, :source_text)
        missing = REQUESTS.reject { |attributes| existing.include?([ attributes[:buyer_name], attributes[:source_text] ]) }
        missing.first(SIZE - count).each do |attributes|
          quote = Quote.create!(attributes.merge(workspace_token: workspace_token, sample_data: true))
          result = RfqProcessing.process(content: quote.source_text, type: "email", matcher: matcher,
            sample_data: true, context: {}, buyer_terms: [], llm: false)
          ApplyResult.call(quote: quote, result: result)
          created << quote
        end
        created
      end
    end
  end
end
