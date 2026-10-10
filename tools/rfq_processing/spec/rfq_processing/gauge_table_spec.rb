# frozen_string_literal: true

RSpec.describe RfqProcessing::GaugeTable do
  it "reads 16 gauge stainless as 0.0625 in, not 0.060" do
    lookup = described_class.lookup(gauge: 16, material: "stainless steel", form: "sheet")
    expect(lookup.thickness_in).to eq(0.0625)
    expect(lookup.table).to eq("stainless steel")
  end

  it "reads 16 gauge mild steel as 0.0598 and galvanized as 0.0635" do
    expect(described_class.lookup(gauge: 16, material: "carbon steel").thickness_in).to eq(0.0598)
    expect(described_class.lookup(gauge: 16, material: "galvanized steel").thickness_in).to eq(0.0635)
  end

  it "uses the tube wall table for tube, even for stainless" do
    expect(described_class.lookup(gauge: 11, material: "carbon steel", form: "square tube").thickness_in).to eq(0.120)
    expect(described_class.lookup(gauge: 14, material: "stainless steel", form: "tube").thickness_in).to eq(0.083)
  end

  it "reports the published alternative for 14 gauge aluminum" do
    lookup = described_class.lookup(gauge: 14, material: "aluminum", form: "sheet")
    expect(lookup.thickness_in).to eq(0.06408)
    expect(lookup.alternative[:value]).to eq(0.063)
  end

  it "returns nil for a gauge that is not in the researched table" do
    expect(described_class.lookup(gauge: 13, material: "stainless steel", form: "sheet")).to be_nil
  end

  it "returns nil when the material is unknown" do
    expect(described_class.lookup(gauge: 16, material: nil, form: "sheet")).to be_nil
  end

  it "lists the four sheet candidates when the material is missing" do
    values = described_class.candidates(gauge: 16, form: "sheet").map { |c| c[:thickness_in] }
    expect(values).to contain_exactly(0.0598, 0.0635, 0.0625, 0.05082)
  end
end
