# Rails runner report, RAILS_ENV=test. Fixture writes roll back; no network calls.
# Pending shared contract: matcher must accept vetted same-word confirmations.
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s
raise "Run in test environment" unless Rails.env.test?

class RulesOnlyTeachingMatcher
  def self.confirmed_terms = @confirmed_terms
  def self.call(text, **options)
    @confirmed_terms = options.fetch(:confirmed_terms, [])
    CatalogMatch::Matcher.call(text, **options.merge(llm: false))
  end
end
class ObservedTeachingIntakeMatcher < QuoteWorkspace::ProcessRfq::IntakeMatcher
  attr_reader :confirmed_terms_received
  def match(**input)
    @confirmed_terms_received = input[:confirmed_terms]
    super
  end
end
catalog = CatalogMatch::Catalog.new(%w[rudco metals])

# A passing taught example is not enough: ordinary processing values must never
# override explicit source numbers without same-phrase teaching provenance.
unsafe = []
[
  ["Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets", "thickness", 0.0625],
  ["Steel shot S-330, 100 lb", "quantity", 104]
].each do |source_text, field, unconfirmed|
  baseline = CatalogMatch::Matcher.call(source_text, client: nil, catalog: catalog, given: {}, llm: false)
  supplied = CatalogMatch::Matcher.call(source_text, client: nil, catalog: catalog,
                                       given: { field => unconfirmed }, llm: false)
  before = baseline.reading.fields[field]
  after = supplied.reading.fields[field]
  raise "Negative control did not read explicit #{field}" unless before && before["source"] == "text"
  next if before == after

  unsafe << "plain given #{field}=#{unconfirmed} changed explicit #{before['value']} (#{before['text'].inspect}) to #{after.inspect}"
end
unless unsafe.empty?
  unsafe.each { |failure| puts "BLOCKED: #{failure}" }
  puts "PENDING: matcher accepts unconfirmed numeric overrides; teaching cannot be accepted until both negative controls pass."
  exit 2
end
puts "Negative controls: plain given values preserve explicit thickness and quantity with their source evidence."
pending = false
ActiveRecord::Base.transaction do
  matcher = ObservedTeachingIntakeMatcher.new(client: nil, catalog: catalog, service: RulesOnlyTeachingMatcher)
  pipeline = RfqProcessing::Pipeline.new(matcher: matcher, llm: false)
  text = "Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets"
  source = Quote.create!(title: "Teaching source", buyer_name: "Teaching diagnostic buyer", workspace_token: "e2e-teaching", source_text: text)
  QuoteWorkspace::ApplyResult.call(quote: source, result: pipeline.process(content: text, type: "email"))
  QuoteWorkspace::TeachBuyerTerm.call(quote: source, quote_line_id: source.quote_lines.sole.id,
    expected_revision: source.review_revision, term: "0.060 in", field: "thickness", value: "0.0625")
  next_quote = Quote.create!(title: "Teaching follow-up", buyer_name: source.buyer_name, workspace_token: source.workspace_token, source_text: text)
  terms = QuoteWorkspace::BuyerContext.for(next_quote).fetch(:buyer_terms)
  raise "Application did not provide validated teaching" if terms.empty?
  taught = pipeline.process(content: text, type: "email", buyer_terms: terms)["lines"].sole
  forwarded = matcher.confirmed_terms_received
  raise "Pipeline did not deliver validated provenance to the adapter" unless forwarded&.any? && forwarded.first.dig("meaning", "provenance", "quote_id") == source.id
  puts "Pipeline -> adapter: confirmed term with validated RFQ/line provenance ACCEPTED"
  puts "Adapter -> matcher: #{RulesOnlyTeachingMatcher.confirmed_terms&.any? ? 'forwarded' : 'PENDING app forwarding'}"
  other = pipeline.process(content: text, type: "email", buyer_terms: [])["lines"].sole
  raise "Taught normalized thickness lost" unless taught.dig("spec", "thickness") == 0.0625
  raise "Taught provenance lost" unless taught.dig("evidence", "thickness", "explanation").include?(source.reference)
  raise "Other buyer inherited teaching" unless other.dig("spec", "thickness") == 0.06 && other["state"] == "needs_buyer"
  raise "Fabricated sheet price" unless taught["unit_price"].nil? && other["unit_price"].nil?
  match = taught.dig("processing", "match")
  mismatches = Array(match["candidates"]).flat_map { |candidate| Array(candidate["mismatches"]) }
  puts "Taught thickness: #{taught.dig('spec', 'thickness')}; matcher #{match['status']} #{match['score']}; mismatches #{mismatches.inspect}"
  if mismatches.any? { |mismatch| mismatch.start_with?("thickness:") }
    puts "PENDING: validated same-word teaching reaches parser but matching still reparses original 0.060 in."
    pending = true
  else
    raise "Taught catalog match was not exact" unless match["status"] == "exact"
    puts "ACCEPTED: exact taught match; other buyer still held; sheet price remains unresolved."
  end
  raise ActiveRecord::Rollback
end
exit 2 if pending
