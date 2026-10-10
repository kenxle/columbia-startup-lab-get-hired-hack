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

  ["KG 50 000", "50,000 KG", "50 000 KG"].each do |quantity|
    it "separates Transnet demand #{quantity} from container weight" do
      r = parse("006828999 STEEL SHOT; TYPE: S 390, MATERIAL: #{quantity} CAST STEEL, MATERIAL GRADE: HRC 40-50, APPLICATION: ABRASIVE SANDING, SHOT LOAD SIZE DESIGNATOR: 1.2 MM; CONTAINER SIZE: 1000 KG PER BOX")
      expect(r["material"]).to eq("steel shot")
      expect(r["form"]).to eq("abrasive")
      expect(r["grade"]).to eq("S-390")
      expect([r["quantity"], r["quantity_unit"]]).to eq([50_000, "kg"])
      expect(r.evidence["quantity"]["text"]).to eq(quantity)
    end
  end

  it "does not mistake package weight for missing demand" do
    r = parse("STEEL SHOT S 390, CONTAINER SIZE: 1000 KG PER BOX")
    expect(r["quantity"]).to be_nil
    expect(r.unknowns.map { |u| u["field"] }).to include("quantity")
  end

  it "reads demand even when packaging appears first" do
    r = parse("STEEL SHOT S 390, 1000 KG PER BOX, 50000 KG")
    expect([r["quantity"], r["quantity_unit"]]).to eq([50_000, "kg"])
  end

  ["in 50 lb bags", "packed in 50 lb bags", "bagged in 50 lb bags"].each do |packaging|
    it "separates #{packaging} from the later total demand" do
      r = parse("Steel shot S-330, #{packaging} 2000 lb COA with each lot")
      expect([r["quantity"], r["quantity_unit"]]).to eq([2000, "lb"])
      expect(r.evidence["quantity"]["text"]).to eq("2000 lb")
    end
  end

  it "does not treat bags with a stated weight as demand when total quantity is absent" do
    r = parse("Steel shot S-330, in 50 lb bags")
    expect(r["quantity"]).to be_nil
    expect(r.unknowns.map { |u| u["field"] }).to include("quantity")
  end


  it "reads glass bead #4 as media size, never brushed finish" do
    r = parse("glass bead #4, 2000 lb")
    expect(r["material"]).to eq("glass bead")
    expect(r["grade"]).to eq("#4")
    expect(r["finish"]).to be_nil
    expect(r.evidence["grade"]["text"]).to eq("#4")
    expect(r["quantity"]).to eq(2000)
  end

  it "retains an explicitly requested No. 4 finish on stainless sheet" do
    expect(parse("304 stainless sheet #4 finish 16 ga 4x8 qty 2")["finish"]).to eq("No. 4")
  end

  it "keeps stainless steel shot distinct and preserves its written alloy" do
    r = parse("stainless steel shot S-330 (304), 2000 lb")
    expect(r["material"]).to eq("stainless steel shot")
    expect(r["grade"]).to eq("S-330 (304)")
    expect(r.evidence["material"]["text"]).to eq("stainless steel shot")
    expect(r.evidence["grade"]["text"]).to eq("S-330 (304)")
  end

  it "does not infer an alloy for stainless shot without one" do
    expect(parse("stainless steel shot S330, 2000 lb")["grade"]).to eq("S-330")
    expect(parse("steel shot S330, 2000 lb")["material"]).to eq("steel shot")
  end

end
