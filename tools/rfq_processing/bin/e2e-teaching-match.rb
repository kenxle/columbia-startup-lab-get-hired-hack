# Read-only Rails runner report, RAILS_ENV=test. No records or network calls.
# Pending shared contract: matcher must accept vetted same-word confirmations.
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s
raise "Run in test environment" unless Rails.env.test?

class RulesOnlyTeachingMatcher
  def self.call(text, **options)
    CatalogMatch::Matcher.call(text, **options.merge(llm: false))
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
matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(client: nil, catalog: catalog, service: RulesOnlyTeachingMatcher)
pipeline = RfqProcessing::Pipeline.new(matcher: matcher, llm: false)
text = "Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets"
term = { "term" => "0.060 in", "meaning" => { "fields" => { "gauge" => 16, "thickness" => 0.0625 } },
  "source" => "taught", "client_name" => "Northline", "times_confirmed" => 1, "confirmed_on" => "RFQ-0001" }
taught = pipeline.process(content: text, type: "email", buyer_terms: [term])["lines"].sole
other = pipeline.process(content: text, type: "email", buyer_terms: [])["lines"].sole
raise "Taught normalized thickness lost" unless taught.dig("spec", "thickness") == 0.0625
raise "Taught provenance lost" unless taught.dig("evidence", "thickness", "explanation").include?("RFQ-0001")
raise "Other buyer inherited teaching" unless other.dig("spec", "thickness") == 0.06 && other["state"] == "needs_buyer"
raise "Fabricated sheet price" unless taught["unit_price"].nil? && other["unit_price"].nil?
match = taught.dig("processing", "match")
mismatches = Array(match["candidates"]).flat_map { |candidate| Array(candidate["mismatches"]) }
puts "Taught thickness: #{taught.dig('spec', 'thickness')}; matcher #{match['status']} #{match['score']}; mismatches #{mismatches.inspect}"
if mismatches.any? { |mismatch| mismatch.start_with?("thickness:") }
  puts "PENDING: vetted same-word teaching reaches parser but matcher reparses original 0.060 in. Shared confirmed-field contract required."
  exit 2
else
  raise "Taught catalog match was not exact" unless match["status"] == "exact"
  puts "ACCEPTED: exact taught match; other buyer still held; sheet price remains unresolved."
end
