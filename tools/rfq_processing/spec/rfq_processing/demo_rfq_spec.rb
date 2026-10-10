# frozen_string_literal: true

# The proposed demo RFQ (Ken writes the email, this lane checks it parses). Built from RudCo's own
# materials per the brief update of 13:00, plus the gauge trap, a contradiction, and hidden requirements.
RSpec.describe "the demo RFQ email" do
  email = File.read(File.join(FIXTURES, "demo_rfq_email.txt"))

  catalog = [
    { "pn" => "RC-STEELSHOT-S330", "form" => "abrasive", "material" => "steel shot", "grade" => "S-330", "unit" => "lb",
      "description" => "Steel Shot S-330", "list_price_usd_per_lb" => 0.4,
      "list_price_source" => { "kind" => "RudCo website list price", "text" => "$0.40/lb", "url" => "https://www.rud-co.com/abrasives/steel-shot" } },
    { "pn" => "RC-AL-P1020-INGOT", "form" => "ingot", "material" => "aluminum", "grade" => "P1020", "unit" => "lb",
      "description" => "P1020 primary aluminum ingot", "list_price_usd_per_lb" => 1.45,
      "list_price_source" => { "kind" => "RudCo website list price", "text" => "$1.45/lb", "url" => "https://www.rud-co.com" } },
    { "pn" => "RC-A36-PLT-500-60X120", "form" => "plate", "material" => "carbon steel", "grade" => "A36", "thickness_in" => 0.5,
      "width_in" => 60, "length_in" => 120, "description" => "A36 plate 1/2 in 60 x 120" },
    { "pn" => "RC-SS304-SHT-16GA-48X96-2B", "form" => "sheet", "material" => "stainless steel", "grade" => "304", "thickness_in" => 0.0625,
      "width_in" => 48, "length_in" => 96, "finish" => "2B", "description" => "304 sheet 16 ga 48 x 96 2B" }
  ]

  result = RfqProcessing.process(content: email, type: "email", catalog: catalog)
  lines = result["lines"]
  by_text = ->(fragment) { lines.find { |l| l["original_text"].include?(fragment) } or raise "no line for #{fragment}" }

  it "finds the eight item lines and skips the prose" do
    expect(lines.size).to eq(8)
    expect(lines.map { |l| l["original_text"] }.join).not_to include("Please quote")
  end

  it "prices the steel shot from RudCo's list price and flags the COA asked for in the email body" do
    line = by_text.call("Steel shot S-330")
    expect(line["state"]).to eq("ready")
    expect(line["unit_price"]).to eq(0.4)
    expect(line["quantity"]).to eq(2000)
    expect(line["quantity_unit"]).to eq("lb")
    expect(line["compliance"].map { |c| c["label"] }).to include("Certificate of analysis (COA) required")
  end

  it "carries the body's MTR and Buy America requirements onto the steel lines" do
    plate = by_text.call("A36 PL")
    labels = plate["compliance"].map { |c| c["label"] }
    expect(labels).to include("Mill test report required", "Buy America / BABA domestic steel")
    expect(plate["compliance"].find { |c| c["label"].start_with?("Mill") }["evidence"]).to eq("MTRs")
  end

  it "reads the ingots" do
    expect(by_text.call("P1020")["state"]).to eq("ready")
    expect(by_text.call("356 ingot")["spec"]["grade"]).to eq("356")
  end

  it "catches the strength contradiction on the A36 plate" do
    line = by_text.call("A36 PL")
    expect(line["state"]).to eq("needs_buyer")
    expect(line["clarification_question"]).to include("A572 Grade 50")
    expect(line["processing"]["question_choices"].map { |c| c["value"] }).to include("A572 Gr 50")
  end

  it "reads 16 ga stainless as 0.0625 in and names the table" do
    line = by_text.call("304 SS sheet 16ga")
    expect(line["spec"]["thickness"]).to eq(0.0625)
    expect(line["evidence"]["thickness"]["explanation"]).to include("stainless steel table is 0.0625 in")
    expect(line["catalog_sku"]).to eq("RC-SS304-SHT-16GA-48X96-2B")
  end

  it "asks about 0.060 versus 16 gauge instead of guessing" do
    line = by_text.call("0.060 in")
    expect(line["state"]).to eq("needs_buyer")
    expect(line["clarification_question"]).to include("16 gauge")
    expect(line["processing"]["question_choices"].map { |c| c["value"] }).to include("0.0625")
  end

  it "asks for the material when a gauge has none, with four choices" do
    line = by_text.call("16 ga sheet 4x8")
    expect(line["state"]).to eq("needs_buyer")
    expect(line["processing"]["question_choices"].size).to eq(4)
  end

  it "reads the tube with the tube wall table and asks nothing about the reading" do
    line = by_text.call("sq tube A500")
    expect(line["spec"]["thickness"]).to eq(0.12)
    expect(line["processing"]["conflicts"]).to be_empty
  end

  it "strips list numbering from the item text" do
    expect(by_text.call("Steel shot S-330")["original_text"]).to start_with("Steel shot")
  end
end
