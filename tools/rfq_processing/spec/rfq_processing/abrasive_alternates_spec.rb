# frozen_string_literal: true

RSpec.describe RfqProcessing::AbrasiveAlternatives do
  let(:input) { "Steel shot S-330 or S-390, 2000 lb, COA required" }
  let(:rows) { JSON.parse(File.read(File.expand_path("../../../../data/rudco/catalog.json", __dir__))) }
  let(:matcher) do
    # The matcher seam returns real sourced catalog rows. Each branch must
    # independently request its exact grade and preserve demand.
    catalog = rows
    Object.new.tap do |object|
      object.define_singleton_method(:match) do |line_text:, spec:, quantity:, quantity_unit:|
        row = catalog.find { |r| r["material"] == spec["material"] && r["grade"] == spec["grade"] }
        candidate = row && row.merge("item_id" => row["pn"], "score" => 1.0, "mismatches" => [], "purchase_unit" => row["unit"])
        { "status" => candidate ? "exact" : "no_match", "threshold" => 0.8, "best" => candidate, "candidates" => [candidate].compact }
      end
    end
  end
  let(:pipeline) { RfqProcessing::Pipeline.new(matcher: matcher, llm: false, jev: false) }

  it "holds the original line and offers both independently priced real catalog grades" do
    line = pipeline.process(type: "email", content: input)["lines"].first
    expect(line["original_text"]).to eq(input)
    expect(line["state"]).to eq("needs_buyer")
    expect(line["unit_price"]).to be_nil
    expect(line["clarification_question"]).to include("RC-STEELSHOT-S330", "RC-STEELSHOT-S390")
    expect(line.dig("processing", "alternates").map { |a| a["catalog_sku"] }).to eq(%w[RC-STEELSHOT-S330 RC-STEELSHOT-S390])
    line.dig("processing", "alternates").each do |option|
      expect(option.values_at("unit_price", "quantity", "quantity_unit", "unresolved_fields")).to eq([0.4, 2000, "lb", []])
      expect(option["price_source"]).to include("RudCo website list price")
    end
  end

  it "lets the buyer choose the second grade with original source evidence" do
    result = pipeline.process(type: "email", content: input)
    line = result["lines"].first
    choice = line.dig("processing", "question_choices").find { |c| c["value"] == "RC-STEELSHOT-S390" }
    expect(choice).not_to be_nil
    updated = RfqProcessing::Answers.apply(previous_result: result, answers: [{"line_id" => line["line_id"], "choice_id" => choice["id"]}], pipeline: pipeline)["lines"].first
    expect(updated["state"]).to eq("ready")
    expect(updated["unit_price"]).to eq(0.4)
    expect(updated.dig("spec", "grade")).to eq("S-390")
    expect(updated.dig("evidence", "grade", "text")).to eq("S-390")
  end

  it "does not generate alternatives from commas" do
    line = pipeline.process(type: "email", content: input.sub(" or ", ", "))["lines"].first
    expect(Array(line.dig("processing", "alternates"))).to be_empty
  end

  it "holds mixed-family alternatives without offering cross-family substitutes" do
    line = pipeline.process(type: "email", content: input.sub("S-390", "G-40"))["lines"].first
    expect(line["state"]).to eq("needs_buyer")
    expect(line["unit_price"]).to be_nil
    expect(Array(line.dig("processing", "alternates"))).to be_empty
  end

  it "does not price incomplete demand" do
    line = pipeline.process(type: "email", content: input.sub(", 2000 lb", ""))["lines"].first
    expect(line["state"]).to eq("needs_buyer")
    expect(line["unit_price"]).to be_nil
    expect(Array(line.dig("processing", "alternates"))).to be_empty
  end
end
