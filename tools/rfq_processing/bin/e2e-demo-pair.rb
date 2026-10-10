# Rails runner, RAILS_ENV=test. Actual intake/answer boundaries, rollback only.
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

raise "Use RAILS_ENV=test" unless Rails.env.test?

ActiveRecord::Base.transaction do
  matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(client: nil,
    catalog: CatalogMatch::Catalog.new(%w[rudco metals]), service: CatalogMatch::Matcher)
  pipeline = RfqProcessing::Pipeline.new(matcher: matcher, llm: false)
  %w[complete incomplete].each do |name|
    text = File.read(Rails.root.join("tools/rfq_processing/spec/fixtures/demo_pair", "#{name}.txt"))
    result = pipeline.process(content: text, type: "email", sample_data: false)
    lines = result.fetch("lines")
    raise "Expected four #{name} lines" unless lines.size == 4
    expected_states = name == "complete" ? %w[ready ready ready ready] : %w[needs_buyer ready ready ready]
    raise "Unexpected #{name} states: #{lines.map { |line| line['state'] }}" unless lines.map { |line| line["state"] } == expected_states

    lines.each_with_index do |line, index|
      raise "Missing catalog item" if line["catalog_sku"].to_s.empty?
      raise "Missing COA evidence" unless line["compliance"].any? { |flag| flag["label"].include?("Certificate of analysis") }
      raise "Missing lead-time disclosure" if line.dig("processing", "lead_time", "text").to_s.empty?
      next unless line["state"] == "ready"

      raise "Wrong sourced price" unless line["unit_price"].to_f == [0.40, 0.42, 0.38, 0.40][index]
      raise "Missing dated price source" if line["price_source"].to_s.empty? || line.dig("benchmark", "as_of").to_s.empty?
      raise "Wrong sale unit" unless line["quantity_unit"] == "lb"
    end
    quote = Quote.create!(title: "Demo pair #{name}", buyer_name: "Northline verification",
      workspace_token: "e2e", source_text: text, sample_data: false)
    QuoteWorkspace::ApplyResult.call(quote: quote, result: result)
    puts "#{name}: ACCEPTED #{lines.count { |line| line['state'] == 'ready' }} Ready; lead times #{lines.map { |line| line.dig('processing', 'lead_time', 'text') }.uniq.inspect}"
    next if name == "complete"

    held, *untouched = quote.quote_lines.order(:position).to_a
    originals = untouched.map(&:attributes)
    raise "Held line was priced" unless held.unit_price.nil?
    answered = QuoteWorkspace::ApplyBuyerAnswer.call(quote: quote, quote_line_id: held.id,
      reviewed_version: quote.review_revision, revision_id: quote.processing_revision["id"], free_text: "2000 lb")
    raise "Quantity answer failed" unless answered.state == "ready" && answered.quantity == 2000 && answered.unit_price == BigDecimal("0.40")
    raise "Unanswered lines changed" unless untouched.map { |line| line.reload.attributes } == originals
    raise "COA lost after answer" unless answered.compliance.any? { |flag| flag["label"].include?("Certificate of analysis") }
    puts "incomplete + buyer answer: ACCEPTED 4 Ready; other lines and COA preserved"
  end
  raise ActiveRecord::Rollback
end
