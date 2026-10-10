# Run from the repo root: SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner tools/rfq_processing/bin/apply-fixtures.rb [args]
# Runs each processing fixture through QuoteWorkspace::ApplyResult inside a
# transaction that is rolled back, so nothing is persisted.
# Usage: BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner -e test <this file> <fixture.json>...
require "json"

ARGV.each do |path|
  result = JSON.parse(File.read(path))
  ActiveRecord::Base.transaction do
    quote = Quote.create!(
      title: "fixture #{File.basename(path)}",
      buyer_name: "Fixture Buyer",
      source_text: result["lines"].map { |l| l["original_text"] }.join("\n"),
      workspace_token: "fixture-token",
      sample_data: true
    )
    begin
      QuoteWorkspace::ApplyResult.call(quote: quote, result: result)
      quote.quote_lines.reload.each do |line|
        puts "#{File.basename(path)}: ACCEPTED  state=#{line.state} quotable=#{line.quotable?} spec_keys=#{line.spec.keys.join(',')} evidence_keys=#{line.evidence.keys.size} compliance=#{line.compliance.size} benchmark=#{line.benchmark ? 'yes' : 'no'}"
      end
    rescue QuoteWorkspace::ApplyResult::InvalidResult => e
      puts "#{File.basename(path)}: REJECTED  #{e.problems.join(' | ')}"
    end
    raise ActiveRecord::Rollback
  end
end
