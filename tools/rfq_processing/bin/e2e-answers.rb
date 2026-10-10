# Run from the repo root: SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner tools/rfq_processing/bin/e2e-answers.rb
# Buyer answers end to end (workflow W3). The demo email goes through the matcher setup the app's intake
# uses (QuoteWorkspace::ProcessRfq: rudco and metals catalogs, CatalogMatch::Matcher, no client memory,
# rules only), then a round of one-click answers, then a whole-RFQ note. Each rerun goes through
# QuoteWorkspace::ApplyResult inside a transaction that is rolled back. Nothing is stored, no API is called.
$LOAD_PATH.unshift File.expand_path("tools/rfq_processing/lib", Dir.pwd)
require "rfq_processing"
require "json"

rfq = File.read(File.expand_path("docs/product/demo_rfq/email.txt", Dir.pwd))
BUYER = RfqProcessing::Answers::BUYER_LOCATION

def show_lines(result)
  result["lines"].each do |l|
    m = l["processing"]["match"] || {}
    puts format("  %-2d %-12s sku=%-28s match=%-9s score=%-4s | %s", l["position"], l["state"], l["catalog_sku"].to_s[0, 28], m["status"], m["score"], l["description"].to_s[0, 60])
    puts "       q: #{l['clarification_question'][0, 120]}" if l["clarification_question"]
    choices = Array(l.dig("processing", "question_choices"))
    puts "       choices: #{choices.map { |c| "#{c['id'].sub(l['line_id'], '')} #{c['field']}=#{c['label'][0, 50]}" }.join(' | ')}" if choices.any?
    puts "       unresolved: #{l['unresolved_fields'].join(', ')}" if l["unresolved_fields"].any?
    puts "       flags: #{l['compliance'].map { |c| c['label'] }.join('; ')}" if l["compliance"].any?
  end
end

def buyer_evidence(line)
  (line["evidence"] || {}).select { |_, ev| ev.is_a?(Hash) && ev["location"] == BUYER }
end

def show_rerun(result, previous)
  puts "revision #{result['revision']['id']}  previous_revision #{result['previous_revision']}  (llm: #{result['revision']['llm'].inspect})"
  puts "changed_line_ids: #{result['changed_line_ids'].inspect}"
  result["warnings"].each { |w| puts "warning: #{w}" } if result["warnings"].any?
  result["lines"].each do |l|
    next unless result["changed_line_ids"].include?(l["line_id"])

    was = previous["lines"].find { |p| p["line_id"] == l["line_id"] }
    m = l["processing"]["match"] || {}
    puts format("  %-2d %s -> %-12s sku=%-28s match=%-9s | %s", l["position"], was["state"], l["state"], l["catalog_sku"].to_s[0, 28], m["status"], l["description"].to_s[0, 50])
    puts "       q: #{l['clarification_question'][0, 120]}" if l["clarification_question"]
    puts "       answered: #{l.dig('processing', 'answered').inspect}"
    buyer_evidence(l).each { |key, ev| puts "       evidence #{key}: #{ev['text'].inspect} (#{ev['explanation'][0, 110]})" }
    puts "       match reason: #{m['reason'].to_s[0, 110]}" if m["reason"].to_s.include?("buyer")
    yield l if block_given?
  end
end

# A simulated buyer. Each pick is read off the choices' field and label; the reasons are the script's,
# not catalog facts, and the rules are listed in the order they are tried.
PICKS = [
  ["thickness_in", /\A0\.0625 in\z/, "scripted answer: 16 gauge (0.0625 in) is acceptable in place of the 0.060 in written"],
  ["catalog_item", /\b2B\b/, "scripted answer: the 2B finish candidate"],
  ["grade", /dual certified/i, "scripted answer: the dual-certified grade, which the matched plate already satisfies"],
  ["material", /\Astainless steel\b/i, "scripted answer: stainless, like the two 304 sheet lines above it"]
].freeze

def pick(line)
  choices = Array(line.dig("processing", "question_choices"))
  return nil if choices.empty?

  PICKS.each do |field, pattern, why|
    choice = choices.find { |c| c["field"] == field && c["label"].to_s.match?(pattern) }
    return [choice, why] if choice
  end
  [choices.first, "no scripted rule for this line; first listed choice"]
end

def apply_result(quote, result, label)
  QuoteWorkspace::ApplyResult.call(quote: quote, result: result)
  stored = quote.reload.processing_revision
  puts "ApplyResult #{label}: ACCEPTED #{quote.quote_lines.reload.size} lines; ready=#{quote.ready_count} held=#{quote.held_count}; stored revision #{stored['id']} llm=#{stored['llm'].inspect}"
rescue QuoteWorkspace::ApplyResult::InvalidResult => e
  raise "ApplyResult #{label}: REJECTED #{e.problems.join(' | ')}"
end

# Stands in for the Claude step so the last check needs no key and no network: the reading is left as the rules read it.
class StubLlm
  def refine(reading, _text) = reading
  def describe = { "provider" => "anthropic", "model" => "stub-model" }
end

ActiveRecord::Base.transaction do
  catalog = CatalogMatch::Catalog.new(%w[rudco metals])
  matcher_class = defined?(QuoteWorkspace::ProcessRfq::IntakeMatcher) ? QuoteWorkspace::ProcessRfq::IntakeMatcher : RfqProcessing::CatalogMatchAdapter
  matcher = matcher_class.new(client: nil, catalog: catalog, service: CatalogMatch::Matcher)
  pipeline = RfqProcessing::Pipeline.new(matcher: matcher, llm: false)
  puts "matcher #{matcher_class.name} (#{catalog.items.size} items: rudco + metals), llm: false"

  puts "\n== 1. First run =="
  first = pipeline.process(content: rfq, type: "email", sample_data: true)
  puts "revision #{first['revision']['id']}  lines #{first['lines'].size}  llm #{first['revision']['llm'].inspect}  warnings #{first['warnings'].inspect}"
  show_lines(first)

  puts "\n== 2. Answers for the held lines that offer choices =="
  answers = []
  first["lines"].each do |l|
    next if l["state"] == "ready"

    choice, why = pick(l)
    if choice.nil?
      puts "  #{l['position']}: no choices (#{l['unresolved_fields'].join(', ')} unresolved); left alone"
      next
    end
    puts "  #{l['position']}: pick #{choice['id']} #{choice['field']}=#{choice['label'].inspect}; #{why}"
    answers << { "line_id" => l["line_id"], "choice_id" => choice["id"], "revision_id" => first["revision"]["id"] }
  end

  puts "\n== 3. Rerun with the choices =="
  rerun1 = RfqProcessing::Answers.apply(previous_result: first, answers: answers, pipeline: pipeline)
  show_rerun(rerun1, first)

  puts "\n== 4. Whole-RFQ answer on top of that rerun =="
  note = "all of it needs DFARS"
  rerun2 = RfqProcessing::Answers.apply(previous_result: rerun1, pipeline: pipeline,
                                        answers: [{ "scope" => "rfq", "free_text" => note, "revision_id" => rerun1["revision"]["id"] }])
  show_rerun(rerun2, rerun1) do |l|
    flag = l["compliance"].find { |c| c["label"].include?("DFARS") }
    puts "       DFARS: #{flag ? "#{flag['label']} (evidence #{flag['evidence'].inspect})" : 'no flag'}"
    kept = buyer_evidence(l).keys
    before = rerun1["lines"].find { |p| p["line_id"] == l["line_id"] }
    lost = buyer_evidence(before).keys - kept
    lost << "catalog item (was #{before['catalog_sku']})" if before["catalog_sku"] && l["catalog_sku"] != before["catalog_sku"]
    puts "       earlier answers: #{lost.empty? ? 'kept' : "LOST #{lost.join(', ')}"}"
  end

  puts "\n== 5. Both reruns through ApplyResult (rolled back) =="
  quote = Quote.create!(title: "e2e answers", buyer_name: "Northline Fabrication", source_text: rfq, workspace_token: "e2e", sample_data: true)
  apply_result(quote, first, "first run")
  apply_result(quote, rerun1, "rerun 1 (choices)")
  apply_result(quote, rerun2, "rerun 2 (whole-RFQ)")

  puts "\n== 6. revision.llm through ApplyResult, with a stub Claude step (no API call) =="
  described = RfqProcessing::Pipeline.new(matcher: matcher, llm: StubLlm.new).process(content: rfq, type: "email", sample_data: true)
  puts "revision.llm #{described['revision']['llm'].inspect}; bounded JSON? #{Quote.valid_processing_metadata?(described['revision'], revision: true)}"
  apply_result(quote, described, "stub llm run")

  puts "\n== 7. Held steel shot answered through the application wrapper =="
  shot_result = pipeline.process(content: "Steel shot S-330\nP1020 aluminum ingot 100 lb", type: "email", sample_data: true)
  apply_result(quote, shot_result, "missing quantity")
  held, untouched = quote.quote_lines.order(:position).to_a
  raise "Shot was not held" unless held.state == "needs_buyer"
  untouched_before = untouched.attributes.deep_dup
  old_revision = quote.processing_revision["id"]
  answered = QuoteWorkspace::ApplyBuyerAnswer.call(quote: quote, quote_line_id: held.id,
    reviewed_version: quote.review_revision, revision_id: old_revision, free_text: "100 lb")
  raise "Shot answer was not Ready at USD 0.40/lb" unless answered.state == "ready" && answered.quantity == 100 && answered.quantity_unit == "lb" && answered.unit_price == BigDecimal("0.40")
  raise "Unanswered line changed" unless untouched.reload.attributes == untouched_before
  raise "Answer did not issue a new revision" if quote.reload.processing_revision["id"] == old_revision
  puts "ApplyBuyerAnswer: ACCEPTED held shot -> Ready, 100 lb at USD 0.40; unanswered line unchanged"

  fixture = JSON.parse(File.read("tools/rfq_processing/spec/fixtures/results/ambiguous_with_options.json"))
  apply_result(quote, fixture, "ambiguous options fixture")
  raise ActiveRecord::Rollback
end
