# frozen_string_literal: true

RSpec.describe RfqProcessing::ResultBuilder do
  rudco_row = { "pn" => "RC-STEELSHOT-S330", "item_id" => "RC-STEELSHOT-S330", "form" => "abrasive", "material" => "steel shot", "grade" => "S-330",
                "description" => "Steel Shot S-330", "unit" => "lb", "list_price_usd_per_lb" => 0.4,
                "list_price_source" => { "url" => "https://www.rud-co.com/abrasives/steel-shot", "kind" => "RudCo website list price", "text" => "$0.40/lb" } }
  metals_row = { "pn" => "RC-A36-PLT-500-60X120", "item_id" => "RC-A36-PLT-500-60X120", "form" => "plate", "material" => "carbon steel", "grade" => "A36",
                 "thickness_in" => 0.5, "width_in" => 60, "length_in" => 120, "description" => "A36 plate 1/2 in 60 x 120" }

  it "prices a RudCo item from its labeled website list price" do
    result = RfqProcessing.process(content: "Steel shot S-330, 2,000 lb, COA with each lot", type: "email", catalog: [rudco_row])
    line = result["lines"].first
    expect(line["state"]).to eq("ready")
    expect(line["unit_price"]).to eq(0.4)
    expect(line["price_source"]).to include("RudCo website list price")
    expect(line["benchmark"]["kind"]).to eq("list_price")
    expect(line["compliance"].map { |c| c["label"] }).to include("Certificate of analysis (COA) required")
  end

  describe "revision.llm" do
    # Stands in for the Claude step: leaves the reading alone and says who it is. No API is called.
    stub_llm = Class.new do
      def refine(reading, _text) = reading
      def describe = { "provider" => "anthropic", "model" => "stub-model" }
    end
    mute_llm = Class.new { def refine(reading, _text) = reading }
    shot = "Steel shot S-330, 2,000 lb"

    it "names the Claude step that ran, as the step describes itself" do
      result = RfqProcessing.process(content: shot, type: "email", catalog: [rudco_row], llm: stub_llm.new)
      expect(result["revision"]["llm"]).to eq("provider" => "anthropic", "model" => "stub-model")
      expect(result["lines"].first["state"]).to eq("ready")
    end

    it "is nil, with the key present, for a rules-only run" do
      result = RfqProcessing.process(content: shot, type: "email", catalog: [rudco_row], llm: false)
      expect(result["revision"]).to include("llm" => nil)
      expect(result["revision"].keys).to eq(%w[id created_at processor llm])
    end

    it "is nil when the step is on but cannot describe itself" do
      result = RfqProcessing.process(content: shot, type: "email", catalog: [rudco_row], llm: mute_llm.new)
      expect(result["revision"]).to include("llm" => nil)
    end
  end

  it "holds a matched line with no price instead of calling it Ready" do
    result = RfqProcessing.process(content: "1/2 A36 PL 5x10 x3", type: "email", catalog: [metals_row])
    line = result["lines"].first
    expect(line["state"]).to eq("needs_buyer")
    expect(line["catalog_sku"]).to eq("RC-A36-PLT-500-60X120")
    expect(line["unresolved_fields"]).to eq(["unit_price"])
    expect(line["clarification_question"]).to include("matched to RC-A36-PLT-500-60X120")
  end
end

RSpec.describe "grounded alternate options" do
  let(:candidate) do
    { "item_id" => "SHOT-A", "description" => "Steel shot S-330", "score" => 0.9, "mismatches" => [],
      "list_price_usd_per_lb" => 0.4, "list_price_source" => { "text" => "$0.40/lb", "kind" => "Fixture list price", "currency" => "USD", "as_of" => "2026-09-01" } }
  end
  let(:match) { { "status" => "ambiguous", "threshold" => 0.8, "best" => nil, "candidates" => [candidate, candidate.merge("item_id" => "SHOT-B")] } }
  let(:matcher) { double(:matcher, match: match) }
  let(:pipeline) { RfqProcessing::Pipeline.new(matcher: matcher, llm: false) }

  it "ties each priced option to a buyer choice and retains its observation date" do
    line = pipeline.process(content: "Steel shot S-330 20 lb", type: "email")["lines"].first
    expect(line["state"]).to eq("needs_buyer")
    expect(line["unit_price"]).to be_nil
    options = line.dig("processing", "alternates")
    expect(options.size).to eq(2)
    options.each do |option|
      expect(option).to include("unit_price" => 0.4, "currency" => "USD", "quantity" => 20, "quantity_unit" => "lb")
      expect(option["benchmark"]["as_of"]).to eq("2026-09-01")
      expect(line.dig("processing", "question_choices")).to include(include("id" => option["choice_id"], "value" => option["item_id"]))
    end
  end

  it "holds per-pound prices for bag quantities and never fabricates currency or dates" do
    options = pipeline.process(content: "Steel shot S-330 20 bags", type: "email")["lines"].first.dig("processing", "alternates")
    expect(options).to all(include("unit_price" => nil, "currency" => nil, "benchmark" => nil, "unresolved_fields" => ["unit_price"]))
    expect(RfqProcessing::ResultBuilder.observation_date({})).to be_nil
    expect(RfqProcessing::ResultBuilder.price_for(candidate.merge("list_price_source" => { "currency" => "EUR" }), quantity_unit: "lb")).to be_nil
  end

  it "never offers no-match, below-threshold, or mismatched candidates as options" do
    match["candidates"] = [candidate.merge("score" => 0.79), candidate.merge("mismatches" => ["grade differs"])]
    expect(pipeline.process(content: "Steel shot S-330 20 lb", type: "email")["lines"].first.dig("processing", "alternates")).to eq([])
    match["status"] = "no_match"
    match["candidates"] = [candidate]
    expect(pipeline.process(content: "Steel shot S-330 20 lb", type: "email")["lines"].first.dig("processing", "alternates")).to eq([])
  end

  it "keeps option and choice identities linked after a free-text rerun" do
    before = pipeline.process(content: "Steel shot S-330 20 lb", type: "email")
    line = before["lines"].first
    after = RfqProcessing::Answers.apply(previous_result: before, pipeline: pipeline, answers: [{ "line_id" => line["line_id"], "free_text" => "thanks" }])["lines"].first
    expect(after.dig("processing", "alternates").map { |o| o.values_at("id", "choice_id") }).to eq(line.dig("processing", "alternates").map { |o| o.values_at("id", "choice_id") })
  end

  it "rejects unsafe item picks without changing the match" do
    [match.merge("status" => "no_match"), match.merge("candidates" => [candidate.merge("score" => 0.79)]),
     match.merge("candidates" => [candidate.merge("mismatches" => ["length differs"])])].each do |unsafe|
      unchanged, conflict = pipeline.pick_item(unsafe, "SHOT-A")
      expect(unchanged).to eq(unsafe)
      expect(conflict["code"]).to eq("chosen_item_rejected")
    end
    picked, conflict = pipeline.pick_item(match, "SHOT-B")
    expect(conflict).to be_nil
    expect(picked["best"]["item_id"]).to eq("SHOT-B")
  end

  it "holds a matched item when its price basis differs from the requested unit" do
    match.merge!("status" => "exact", "best" => candidate)
    line = pipeline.process(content: "Steel shot S-330 20 bags", type: "email")["lines"].first
    expect(line).to include("state" => "needs_buyer", "unit_price" => nil, "unresolved_fields" => ["unit_price"])
  end
end

RSpec.describe "RudCo snapshot dates" do
  it "uses the checked-in manifest date and preserves a row's own observation" do
    adapter = RfqProcessing::CatalogMatchAdapter.new
    entry = { "catalog" => "rudco", "list_price_usd_per_lb" => 0.4, "list_price_source" => { "text" => "$0.40/lb", "url" => "https://www.rud-co.com/abrasives/steel-shot" } }
    manifest = JSON.parse(File.read(File.expand_path("../../../../data/rudco/source_manifest.json", __dir__)))
    enriched = adapter.send(:with_observation_date, entry)
    expect(RfqProcessing::ResultBuilder.observation_date(enriched)).to eq(manifest["fetched_at"])
    expect(entry["list_price_source"]).not_to have_key("observed_at")
    own_date = entry.merge("list_price_source" => { "as_of" => "2026-09-01" })
    expect(adapter.send(:with_observation_date, own_date)).to eq(own_date)
  end
end

RSpec.describe "catalog candidate price evidence" do
  let(:price) do
    { "unit_price" => "0.4", "currency" => "USD", "price_source" => "RudCo observed website listing",
      "benchmark" => { "name" => "Website list price", "as_of" => "2026-10-10T17:04:39Z", "kind" => "website_list_price", "unit" => "USD per lb", "explanation" => "Product only; freight excluded." } }
  end
  let(:entry) { { "item_id" => "S330", "score" => 1.0, "mismatches" => [], "price" => price } }

  it "accepts matching labeled dated USD evidence and preserves its original benchmark" do
    expect(RfqProcessing::ResultBuilder.price_for(entry, quantity_unit: "lb")).to eq(unit_price: 0.4, source: price["price_source"])
    expect(RfqProcessing::ResultBuilder.benchmark_for(entry)).to eq(price["benchmark"].merge("kind" => "list_price"))
    expect(price["benchmark"]["kind"]).to eq("website_list_price")
  end

  it "holds wrong units, non-USD currency, invalid prices, missing dates and unlabeled sources" do
    rejected = [price.merge("currency" => "EUR"), price.merge("unit_price" => "NaN"), price.merge("unit_price" => -1),
      price.merge("price_source" => ""), price.merge("benchmark" => price["benchmark"].merge("as_of" => "unknown")),
      price.merge("benchmark" => price["benchmark"].except("as_of")), price.merge("benchmark" => price["benchmark"].merge("unit" => "USD per bag"))]
    rejected.each do |bad|
      # Invalid new evidence must not fall back to a legacy price on the row.
      row = entry.merge("price" => bad, "list_price_usd_per_lb" => 0.4, "list_price_source" => { "text" => "$0.40/lb" })
      expect(RfqProcessing::ResultBuilder.price_for(row, quantity_unit: "lb")).to be_nil
    end
    expect(RfqProcessing::ResultBuilder.price_for(entry, quantity_unit: "kg")).to be_nil
  end

  it "carries the same candidate price on the service adapter path" do
    benchmark = Class.new
    benchmark.define_singleton_method(:for) { |_item| { "unit_price" => 0.4, "currency" => "USD", "price_source" => "catalog source", "benchmark" => {} } }
    stub_const("CatalogMatch::Benchmark", benchmark)
    candidate = Struct.new(:item, :checks, :confidence).new({ "item_id" => "S330" }, [], 100)
    converted = RfqProcessing::CatalogMatchAdapter.new.send(:convert, candidate)
    expect(converted["price"]).to include("unit_price" => "0.4", "currency" => "USD", "price_source" => "catalog source")
  end
end

RSpec.describe "legacy source evidence safeguards" do
  let(:builder) { RfqProcessing::ResultBuilder }
  let(:list) { { "list_price_usd_per_lb" => 0.4, "list_price_source" => { "kind" => "Supplier list observation", "text" => "$0.40/lb" } } }

  it "does not fall back when a candidate explicitly supplies an invalid price" do
    [false, nil, "", []].each do |invalid|
      expect(builder.price_for(list.merge("price" => invalid), quantity_unit: "lb")).to be_nil
    end
  end

  it "requires two distinct dated observations and a supported range for a dealer midpoint" do
    row = { "market_reference" => { "midpoint_usd_each" => 3 } }
    expect(builder.price_for(row, quantity_unit: "each")).to be_nil
    row["market_reference"].merge!("source_count" => 2, "min_usd_each" => 2, "max_usd_each" => 4, "as_of" => "2026-10-09")
    row["observation_ids"] = ["dealer-a-item", "dealer-b-item"]
    expect(builder.price_for(row, quantity_unit: "each")[:unit_price]).to eq(3)
    expect(builder.price_for(row.merge("observation_ids" => ["same", "same"]), quantity_unit: "each")).to be_nil
    row["market_reference"].delete("as_of")
    expect(builder.price_for(row, quantity_unit: "each")).to be_nil
  end

  it "never invents a supplier or URL for a list reference" do
    expect(builder.price_for(list.merge("list_price_source" => { "text" => "unverified listing" }), quantity_unit: "lb")).to be_nil
    price = builder.price_for(list, quantity_unit: "lb")
    expect(price[:source]).to include("Supplier list observation", "date unknown")
    expect(price[:source]).not_to include("rud-co.com", "RudCo", "Website")
    expect(builder.benchmark_for(list)["explanation"]).not_to include("RudCo")
  end
end

RSpec.describe "alternate readiness holds" do
  let(:candidate) do
    { "item_id" => "OPTION-A", "score" => 1.0, "mismatches" => [], "list_price_usd_per_lb" => 0.4,
      "list_price_source" => { "kind" => "Fixture supplier list price", "text" => "$0.40/lb", "as_of" => "2026-10-09" } }
  end
  let(:matcher) { double(:matcher, match: { "status" => "ambiguous", "best" => nil, "threshold" => 0.8, "candidates" => [candidate, candidate.merge("item_id" => "OPTION-B")] }) }
  let(:pipeline) { RfqProcessing::Pipeline.new(matcher: matcher, llm: false) }

  it "retains missing quantity even when candidate unit prices and purchase unit are known" do
    source = RfqProcessing::Extractor::Line.new(text: "Steel shot S-330", location: "line 1")
    line = pipeline.process_line(source, position: 1, overrides: { "quantity_unit" => { "value" => "lb", "text" => "quote by the pound" } })
    expect(line["unresolved_fields"]).to include("quantity")
    options = line.dig("processing", "alternates")
    expect(options.size).to eq(2)
    options.each do |option|
      expect(option["unit_price"]).to eq(0.4)
      expect(option["quantity"]).to be_nil
      expect(option["unresolved_fields"]).to include("quantity")
    end
  end

  it "retains conflicting thickness instead of treating a priced option as settled" do
    line = pipeline.process(content: "304 SS sheet 16 ga 0.060 in, 48 x 96, 10 lb", type: "email")["lines"].first
    expect(line["unresolved_fields"]).to include("thickness")
    options = line.dig("processing", "alternates")
    expect(options.size).to eq(2)
    expect(options).to all(include("unit_price" => 0.4, "unresolved_fields" => include("thickness")))
  end

  it "removes only item ambiguity when a complete line has priced options" do
    line = pipeline.process(content: "Steel shot S-330 10 lb", type: "email")["lines"].first
    expect(line["unresolved_fields"]).to include("catalog item")
    expect(line.dig("processing", "alternates")).to all(include("unit_price" => 0.4, "unresolved_fields" => []))
  end
end
