# Run from the repo root: SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner tools/rfq_processing/bin/e2e-apply-result.rb [args]
# End to end: sample RFQ text -> RfqProcessing pipeline -> QuoteWorkspace::ApplyResult (rolled back).
# Usage: RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner <this file>
$LOAD_PATH.unshift File.expand_path("tools/rfq_processing/lib", Dir.pwd)
require "rfq_processing"
require "json"

rfq = <<~TEXT
  Hi, please quote the following for delivery next month:
  AN3-13A bolts, 100 ea, need C of C
  AN3 bolts, drilled, 50 pcs
  304 SS sheet 16ga 4x8, 20 sheets, MTRs required
  Stainless 304, 0.060 in, 48 x 96 x 10
  16 ga sheet 4x8 qty 20
  1-1/2 sq tube A500 C 11ga 24ft x8
  Thanks, Northline Fabrication
TEXT

catalog = JSON.parse(File.read("data/aviation/catalog.json"))
result = RfqProcessing.process(content: rfq, type: "email", catalog: catalog)
puts "revision #{result['revision']['id']}  lines #{result['lines'].size}  warnings #{result['warnings']}"
result["lines"].each do |l|
  puts format("  %-2d %-12s sku=%-8s price=%-6s | %s", l["position"], l["state"], l["catalog_sku"], l["unit_price"], l["description"][0, 70])
  puts "       q: #{l['clarification_question'][0, 110]}" if l["clarification_question"]
  puts "       flags: #{l['compliance'].map { |c| c['label'] }.join('; ')}" if l["compliance"].any?
end

ActiveRecord::Base.transaction do
  quote = Quote.create!(title: "end to end", buyer_name: "Northline Fabrication", source_text: rfq, workspace_token: "e2e", sample_data: true)
  begin
    QuoteWorkspace::ApplyResult.call(quote: quote, result: result)
    puts "ApplyResult: ACCEPTED #{quote.quote_lines.reload.size} lines; ready=#{quote.ready_count} held=#{quote.held_count} subtotal=#{quote.subtotal}"
  rescue QuoteWorkspace::ApplyResult::InvalidResult => e
    puts "ApplyResult: REJECTED #{e.problems.join(' | ')}"
  end
  raise ActiveRecord::Rollback
end
File.write(File.expand_path("../../../tmp/e2e_result.json", __dir__), JSON.pretty_generate(result)) rescue nil
