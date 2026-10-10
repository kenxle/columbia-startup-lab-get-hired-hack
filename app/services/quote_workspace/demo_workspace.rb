require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

module QuoteWorkspace
  # Fictional development RFQs, including constructed sent history. This never
  # sends mail or replaces existing RFQs. The fixed Demo fixture stays separate.
  class DemoWorkspace
    SIZE = 12
    REQUESTS = [
      { title: "Steel shot replenishment", buyer_name: "Hudson Surface Prep", age_hours: 23.5, approve: true,
        source_text: "S-330 steel shot, 100 lb" },
      { title: "Structural plate order", buyer_name: "Harbor Fabrication", age_hours: 22,
        source_text: "A36 plate 1/4 x 48 x 96, qty 5" },
      { title: "Blast room media restock", buyer_name: "Cedar Foundry", age_hours: 19,
        source_text: "S-170 steel shot, 200 lb\nS-330 steel shot, 500 lb\nS-390 steel shot, 100 lb" },
      { title: "Aerospace sheet request", buyer_name: "Beacon Machine Works", age_hours: 25,
        source_text: "7075-T6 aluminum sheet .125 x 48 x 144, qty 2" },
      { title: "Shop materials and blasting media", buyer_name: "Harbor Fabrication", age_hours: 14,
        source_text: "S-330 steel shot, 250 lb\nPlate 1/4 x 48 x 96, qty 10\n304 SS sheet 16ga 4x8, qty 5\nG-40 steel grit, 100 lb\nP1020 aluminum ingot, 500 lb" },
      { title: "Peening line refill", buyer_name: "Cedar Foundry", age_hours: 9, approve: true,
        source_text: "S-230 steel shot, 300 lb" },
      { title: "Plate dimensions to confirm", buyer_name: "Northline Fabrication", age_hours: 4,
        source_text: "Steel plate 1/4, qty 12" },
      { title: "Weekly blast media delivery", buyer_name: "Hudson Surface Prep", age_hours: 4, sent_hours: 3,
        source_text: "S-330 steel shot, 400 lb" },
      { title: "High strength aluminum panels", buyer_name: "Beacon Machine Works", age_hours: 23,
        source_text: "7075-T6 aluminum sheet .250 x 48 x 144, qty 3" },
      { title: "Foundry cleaning media", buyer_name: "Cedar Foundry", age_hours: 2, sent_hours: 1,
        source_text: "S-170 steel shot, 150 lb" },
      { title: "Afternoon media order", buyer_name: "Summit Coatings", age_hours: 0.5,
        source_text: "S-460 steel shot, 200 lb" }
    ].freeze

    def self.seed_if_empty!(workspace_token:)
      return [] unless Rails.env.development?
      return [] if Quote.for_workspace(workspace_token).exists?

      populate!(workspace_token: workspace_token)
    end

    # Explicit local demo maintenance only. Never called by a page request.
    # Leave updated_at untouched: it is the reviewed content revision, including
    # the revision recorded by a constructed sent receipt.
    def self.refresh_timing!(workspace_token: nil, now: Time.current)
      raise ArgumentError, "Demo timing can only be refreshed in development" unless Rails.env.development?

      scope = Quote.where(sample_data: true)
      scope = scope.for_workspace(workspace_token) if workspace_token
      recipes = [ { title: Demo::TITLE, buyer_name: Demo::BUYER_NAME, source_text: Demo::SOURCE_TEXT,
        age_hours: 27 } ] + REQUESTS
      counts = { refreshed: 0, skipped: 0 }
      scope.find_each do |quote|
        quote.with_lock do
          recipe = recipes.find do |candidate|
            candidate.values_at(:title, :buyer_name, :source_text) == quote.attributes.values_at("title", "buyer_name", "source_text")
          end
          lines = quote.quote_lines.reload.to_a
          pristine = recipe && quote.source_bytes.nil? && quote.processing_runs.none? && lines.any? &&
            lines.all? { |line| Array(line.edited_fields).empty? && line.updated_at == line.created_at } &&
            (quote.updated_at - lines.map(&:created_at).max).between?(0, 2)
          expected_approval = recipe && (recipe[:approve] || recipe[:sent_hours]).present?
          expected_sent = recipe && recipe[:sent_hours].present?
          history_matches = quote.approved? == !!expected_approval && quote.sent? == !!expected_sent &&
            (expected_sent || (quote.sent_at.nil? && quote.sent_review_revision.nil?))
          unless pristine && history_matches
            counts[:skipped] += 1
            next
          end

          timestamps = { created_at: now - recipe[:age_hours].hours }
          if expected_sent
            timestamps[:sent_at] = now - recipe[:sent_hours].hours
            timestamps[:approved_at] = timestamps[:sent_at]
          elsif expected_approval
            timestamps[:approved_at] = now
          end
          quote.update_columns(timestamps)
          counts[:refreshed] += 1
        end
      end
      counts
    end

    def self.populate!(workspace_token:)
      return [] unless Rails.env.development?
      raise ArgumentError, "A workspace token is required" if workspace_token.blank?

      Quote.transaction do
        count = Quote.for_workspace(workspace_token).count
        return [] if count >= SIZE

        now = Time.current
        created = []
        unless Quote.for_workspace(workspace_token).exists?(buyer_name: Demo::BUYER_NAME, source_text: Demo::SOURCE_TEXT)
          quote = Demo.create!(workspace_token: workspace_token)
          quote.update_columns(created_at: now - 27.hours)
          created << quote
          count += 1
        end
        catalog = CatalogMatch::Catalog.new(%w[rudco metals])
        matcher = ProcessRfq::IntakeMatcher.new(client: nil, catalog: catalog, service: CatalogMatch::Matcher)
        existing = Quote.for_workspace(workspace_token).pluck(:buyer_name, :source_text)
        missing = REQUESTS.reject { |attributes| existing.include?([ attributes[:buyer_name], attributes[:source_text] ]) }
        missing.first(SIZE - count).each do |recipe|
          quote = Quote.create!(recipe.except(:age_hours, :sent_hours, :approve).merge(
            workspace_token: workspace_token, sample_data: true, created_at: now - recipe[:age_hours].hours))
          result = RfqProcessing.process(content: quote.source_text, type: "email", matcher: matcher,
            sample_data: true, context: {}, buyer_terms: [], llm: false)
          ApplyResult.call(quote: quote, result: result, preview_questions: false)
          if recipe[:approve] || recipe[:sent_hours]
            raise "Approved demo RFQ must have only ready lines" unless quote.held_count.zero? && quote.ready_count.positive?

            quote.approve!(approved_time: recipe[:sent_hours] ? now - recipe[:sent_hours].hours : now)
          end
          if recipe[:sent_hours]
            sent_time = now - recipe[:sent_hours].hours
            # Constructed history only. Preserve the reviewed version while
            # recording sent state, without invoking any delivery service.
            quote.update_columns(sent_at: sent_time, sent_review_revision: quote.review_revision)
          end
          created << quote
        end
        created
      end
    end
  end
end
