# Run from the repo root: SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner tools/rfq_processing/bin/e2e-tisch-matcher.rb [args]
# End to end through Tisch's Rails matcher via the adapter, then into ApplyResult (rolled back).
# Usage: RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner <this file>
$LOAD_PATH.unshift File.expand_path("tools/rfq_processing/lib", Dir.pwd)
require "rfq_processing"
require "json"

rfq = <<~TEXT
  Please quote:
  304 SS sheet 16ga 4x8, 20 sheets, MTRs required
  Stainless 304, 0.060 in, 48 x 96, 10 sheets
  Steel shot S-330, 2,000 lb, COA with each lot
  P1020 aluminum ingot 5,000 lbs
  1/2 A36 PL 5x10 x3
  AN3-13A bolts, 100 ea
TEXT

ActiveRecord::Base.transaction do
  client = Client.create!(name: "Northline Fabrication", workspace_token: "e2e") rescue nil
  matcher = RfqProcessing::CatalogMatchAdapter.new(client: client)
  result = RfqProcessing.process(content: rfq, type: "email", matcher: matcher)
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
    puts "ApplyResult: REJECTED #{e.problems.join(' | ')}"
  end
  raise ActiveRecord::Rollback
end
