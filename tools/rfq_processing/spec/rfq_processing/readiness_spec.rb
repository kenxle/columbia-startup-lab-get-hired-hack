# frozen_string_literal: true

RSpec.describe RfqProcessing::Readiness do
  let(:screw) { "1/4-20 x 1 in hex cap screws, zinc plated, 500 pcs" }
  let(:reading) { RfqProcessing::RulesParser.parse(screw) }

  it "labels the Northline screw No match while preserving missing material and source" do
    email = File.read(File.expand_path("../../../../docs/product/demo_rfq/email.txt", __dir__))
    line = RfqProcessing.process(content: email, type: "email", catalog: [], llm: false)["lines"].find { |entry| entry["original_text"] == screw }
    expect(line).to include("state" => "no_match", "unit_price" => nil, "catalog_sku" => nil, "unresolved_fields" => ["material"])
    expect(line["spec"]["material"]).to be_nil
    expect(line["clarification_question"]).to include("No match in the current catalog")
    expect(line["clarification_question"]).not_to include("Please give the material")
  end

  it "still holds missing screw material for exact and ambiguous catalog matches" do
    %w[exact ambiguous].each do |status|
      decision = described_class.decide(reading, match: { "status" => status, "candidates" => [] })
      expect(decision.state).to eq("needs_buyer")
      expect(decision.unresolved_fields).to include("material")
    end
  end

  it "does not suppress other missing fields or conflicts on unsupported screws" do
    reading.unknowns << { "field" => "quantity" }
    expect(described_class.decide(reading, match: { "status" => "no_match" }).state).to eq("needs_buyer")
    reading.unknowns.pop
    reading.conflicts << { "fields" => ["material"], "message" => "Confirm the contradictory materials." }
    expect(described_class.decide(reading, match: { "status" => "no_match" }).state).to eq("needs_buyer")
  end

  it "does not treat an absent matcher result as an explicit no match" do
    expect(described_class.decide(reading).state).to eq("needs_buyer")
  end
end
