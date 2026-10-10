# Run from the repo root: SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner tools/rfq_processing/bin/e2e-tisch-matcher.rb [args]
# End to end through Tisch's Rails matcher via the adapter, then into ApplyResult (rolled back).
# Usage: RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner <this file>
$LOAD_PATH.unshift File.expand_path("tools/rfq_processing/lib", Dir.pwd)
require "rfq_processing"
require "json"

rfq = File.read("docs/product/demo_rfq/email.txt")

ActiveRecord::Base.transaction do
  client = Client.create!(name: "Northline Fabrication", workspace_token: "e2e") rescue nil
  matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(client: nil, catalog: CatalogMatch::Catalog.new(%w[rudco metals]), service: CatalogMatch::Matcher)
  result = RfqProcessing.process(content: rfq, type: "email", matcher: matcher, llm: false)
  puts "revision #{result['revision']['id']}  lines #{result['lines'].size}"
  result["lines"].each do |l|
    m = l["processing"]["match"] || {}
    puts format("  %-2d %-12s sku=%-28s match=%-9s score=%-4s | %s", l["position"], l["state"], l["catalog_sku"].to_s[0, 28], m["status"], m["score"], l["description"].to_s[0, 60])
    puts "       q: #{l['clarification_question'][0, 120]}" if l["clarification_question"]
    puts "       flags: #{l['compliance'].map { |c| c['label'] }.join('; ')}" if l["compliance"].any?
  end
  quote = Quote.create!(title: "e2e tisch", buyer_name: "Northline Fabrication", source_text: rfq, workspace_token: "e2e", sample_data: true)
  begin
    QuoteWorkspace::ApplyResult.call(quote: quote, result: result)
    puts "ApplyResult: ACCEPTED #{quote.quote_lines.reload.size} lines; ready=#{quote.ready_count} held=#{quote.held_count}"
  rescue QuoteWorkspace::ApplyResult::InvalidResult => e
    raise "ApplyResult: REJECTED #{e.problems.join(' | ')}"
  end
  raise ActiveRecord::Rollback
end
