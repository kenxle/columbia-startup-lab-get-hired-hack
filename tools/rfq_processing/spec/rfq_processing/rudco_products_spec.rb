# frozen_string_literal: true

# RudCo's own products from Ken's brief update (13:00): steel shot, grit, beads, aluminum ingot, sold by weight or bag.
RSpec.describe "RudCo products through the parser" do
  def parse(text) = RfqProcessing::RulesParser.parse(text)

  it "reads steel shot S-330 sold by the pound" do
    r = parse("Steel shot S-330, 2,000 lb")
    expect(r["material"]).to eq("steel shot")
    expect(r["form"]).to eq("abrasive")
    expect(r["grade"]).to eq("S-330")
    expect(r["quantity"]).to eq(2000)
    expect(r["quantity_unit"]).to eq("lb")
    expect(r.unknowns).to be_empty
  end

  it "reads steel grit by the bag" do
    r = parse("G-40 steel grit, 40 bags")
    expect(r["material"]).to eq("steel grit")
    expect(r["grade"]).to eq("G-40")
    expect([r["quantity"], r["quantity_unit"]]).to eq([40, "bag"])
  end

  it "reads P1020 aluminum ingot" do
    r = parse("P1020 aluminum ingot 5,000 lbs")
    expect(r["material"]).to eq("aluminum")
    expect(r["form"]).to eq("ingot")
    expect(r["grade"]).to eq("P1020")
    expect([r["quantity"], r["quantity_unit"]]).to eq([5000, "lb"])
  end

  it "reads aluminum 356 ingot and asks for the quantity when it is missing" do
    r = parse("Aluminum 356 ingot")
    expect(r["grade"]).to eq("356")
    expect(r["form"]).to eq("ingot")
    expect(r.unknowns.map { |u| u["field"] }).to include("quantity")
  end

  it "does not read steel shot as carbon steel sheet" do
    r = parse("steel shot S-170 500 lb")
    expect(r["material"]).to eq("steel shot")
    expect(r["form"]).to eq("abrasive")
  end

  it "reads glass bead and aluminum oxide" do
    expect(parse("glass bead, 10 bags")["material"]).to eq("glass bead")
    expect(parse("aluminum oxide 46 grit 50 lb")["material"]).to eq("aluminum oxide")
  end
end
