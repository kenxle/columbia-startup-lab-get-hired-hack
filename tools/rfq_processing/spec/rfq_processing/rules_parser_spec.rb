# frozen_string_literal: true

RSpec.describe RfqProcessing::RulesParser do
  def parse(text) = described_class.parse(text)

  describe "the PRD examples" do
    it "reads 304 SS sheet 16ga 4x8 with the stainless table and 48 x 96" do
      r = parse("304 SS sheet 16ga 4x8")
      expect(r["material"]).to eq("stainless steel")
      expect(r["grade"]).to eq("304")
      expect(r["form"]).to eq("sheet")
      expect(r["thickness_in"]).to eq(0.0625)
      expect(r["width_in"]).to eq(48)
      expect(r["length_in"]).to eq(96)
      expect(r.evidence["thickness_in"]["text"]).to eq("16ga")
      expect(r.evidence["thickness_in"]["explanation"]).to include("stainless steel table is 0.0625")
      expect(r.unknowns.map { |u| u["field"] }).to include("quantity")
    end

    it "keeps 0.060 exact and asks about 16 gauge" do
      r = parse("Stainless 304, 0.060 in, 48 x 96")
      expect(r["thickness_in"]).to eq(0.06)
      expect(r["width_in"]).to eq(48)
      expect(r["length_in"]).to eq(96)
      expect(r.conflicts.map { |c| c["code"] }).to include("decimal_near_gauge")
    end
  end

  describe "the Iowa verbatim lines" do
    it "T1: 304-2B, 4 x 10, 48 x 120 x 16 Gauge, 19 EA" do
      r = parse('Stainless Steel Sheets Type 304-2B / Stainless Sheets 4 x 10 / 48" x 120" long x 16 Gauge / 19 EA')
      expect(r["material"]).to eq("stainless steel")
      expect(r["grade"]).to eq("304")
      expect(r["finish"]).to eq("2B")
      expect(r["form"]).to eq("sheet")
      expect(r["thickness_in"]).to eq(0.0625)
      expect(r["quantity"]).to eq(19)
      expect([r["width_in"], r["length_in"]]).to eq([48, 120])
    end

    it "T3: square tube with two specs is a conflict" do
      r = parse(%q(Square Tube A513-A500 Grade B / 2" x 2" x 24' long x .188 thick))
      expect(r["form"]).to eq("square tube")
      expect(r["side_a_in"]).to eq(2)
      expect(r["side_b_in"]).to eq(2)
      expect(r["length_in"]).to eq(288)
      expect(r["wall_in"]).to eq(0.188)
      expect(r.conflicts.map { |c| c["code"] }).to include("spec_conflict")
    end

    it "T5: hot rolled strip CQ-A36 3 x 20' x 1/8" do
      r = parse(%q(Hot Rolled Strips CQ-A36 / 3" x 20' long x 1/8" thick))
      expect(r["material"]).to eq("carbon steel")
      expect(r["form"]).to eq("flat bar")
      expect(r["width_in"]).to eq(3)
      expect(r["length_in"]).to eq(240)
      expect(r["thickness_in"]).to eq(0.125)
      expect(r.conflicts.map { |c| c["code"] }).to include("spec_conflict")
    end

    it "T7: aluminum flat 6061-T6 1 x 12' x 1/8" do
      r = parse(%q(Aluminum Flat 6061-T6 / 1" x 12' Long x 1/8" thick))
      expect(r["material"]).to eq("aluminum")
      expect(r["grade"]).to eq("6061")
      expect(r["temper"]).to eq("T6")
      expect(r["width_in"]).to eq(1)
      expect(r["length_in"]).to eq(144)
      expect(r["thickness_in"]).to eq(0.125)
    end
  end

  describe "constructed lines" do
    it "T12: a gauge with no material cannot be read" do
      r = parse("16 ga sheet 4x8 qty 20")
      expect(r["material"]).to be_nil
      expect(r["thickness_in"]).to be_nil
      expect(r["quantity"]).to eq(20)
      expect(r.conflicts.map { |c| c["code"] }).to include("material_missing_with_gauge")
    end

    it "T13: galvanized uses its own table" do
      r = parse("16 ga galv 4x10 x 25")
      expect(r["material"]).to eq("galvanized steel")
      expect(r["thickness_in"]).to eq(0.0635)
      expect([r["width_in"], r["length_in"]]).to eq([48, 120])
      expect(r["quantity"]).to eq(25)
    end

    it "T16: a yield above A36 is a strength mismatch" do
      r = parse("1/2 A36 PL 5x10 x3 min yield 50 ksi")
      expect(r["form"]).to eq("plate")
      expect(r["thickness_in"]).to eq(0.5)
      expect([r["width_in"], r["length_in"]]).to eq([60, 120])
      expect(r["quantity"]).to eq(3)
      expect(r.conflicts.map { |c| c["code"] }).to include("strength_mismatch")
    end

    it "T19: A53 on square tube is a shape conflict" do
      r = parse("2x2 sq tube A53 Gr B .120 24ft")
      expect(r["form"]).to eq("square tube")
      expect(r["wall_in"]).to eq(0.12)
      expect(r["length_in"]).to eq(288)
      expect(r.conflicts.map { |c| c["code"] }).to include("shape_vs_spec")
    end

    it "T25: 11 gauge on A500 tube uses the tube wall table and asks nothing" do
      r = parse("1-1/2 sq tube A500 C 11ga 24ft x8")
      expect(r["form"]).to eq("square tube")
      expect(r["side_a_in"]).to eq(1.5)
      expect(r["wall_in"]).to eq(0.12)
      expect(r["length_in"]).to eq(288)
      expect(r["quantity"]).to eq(8)
      expect(r["standard"]).to eq("A500 Grade C")
      expect(r.conflicts).to be_empty
    end

    it "T24: plate with three numbers reads thickness first" do
      r = parse("6061-T651 plate 2 x 12 x 24 x4")
      expect(r["thickness_in"]).to eq(2)
      expect([r["width_in"], r["length_in"]]).to eq([12, 24])
      expect(r["quantity"]).to eq(4)
      expect(r["temper"]).to eq("T651")
    end

    it "T21: round bar with A276" do
      r = parse("304 rd bar 2in A276 12ft x10")
      expect(r["form"]).to eq("round bar")
      expect(r["diameter_in"]).to eq(2)
      expect(r["length_in"]).to eq(144)
      expect(r["quantity"]).to eq(10)
      expect(r["standard"]).to eq("A276")
    end
  end

  describe "hardware" do
    it "reads an AN part number" do
      r = parse("AN3-13A bolts, 100 ea, need C of C")
      expect(r["part_number"]).to eq("AN3-13A")
      expect(r["quantity"]).to eq(100)
      expect(r["form"]).to eq("hex-head bolt")
    end

    it "flags a family without a dash number" do
      r = parse("AN3 bolts, drilled, 50 pcs")
      expect(r["part_number"]).to be_nil
      expect(r["part_family"]).to eq("AN3")
      expect(r.unknowns.map { |u| u["field"] }).to include("part_number")
    end
  end

  it "recognizes the final screw line but holds its unspecified material" do
    r = parse("1/4-20 x 1 in hex cap screws, zinc plated, 500 pcs")
    expect(r["form"]).to eq("screw")
    expect(r["quantity"]).to eq(500)
    expect(r["material"]).to be_nil
    expect(r.unknowns.map { |u| u["field"] }).to include("material")
    expect(RfqProcessing::Readiness.decide(r, match: { "status" => "exact" }).state).to eq("needs_buyer")
  end

  it "reads the documented Gage x size spelling without turning width into quantity" do
    r = parse("STAINLESS Steel 2B T-304 - 16 Gage x 4 x 8 or similar")
    expect(r["gauge"]).to eq(16)
    expect(r["thickness_in"]).to eq(0.0625)
    expect([r["width_in"], r["length_in"]]).to eq([48, 96])
    expect(r["quantity"]).to be_nil
    expect(r.unknowns.map { |u| u["field"] }).to include("quantity")
    expect(r.evidence["width_in"]["explanation"]).to include("feet")
  end

  it "keeps explicit inches instead of applying the sheet feet shorthand" do
    r = parse('304 stainless sheet 16 Gage x 4" x 8" qty 2')
    expect([r["width_in"], r["length_in"]]).to eq([4, 8])
    expect(r["quantity"]).to eq(2)
  end

  it "does not turn 18-8ss into an assumed stainless grade" do
    r = parse("8-32 x3/8 flat head socket caps in 18-8ss")
    expect(r["grade"]).to be_nil
  end

  describe "buyer terms (workflow step 9, demo beat 8)" do
    let(:taught) do
      { "term" => "16 ga", "meaning" => { "fields" => { "thickness" => 0.0625 } }, "source" => "taught",
        "client_name" => "Northline", "confirmed_on" => "RFQ-0001" }
    end
    let(:line) { "304 SS sheet 16 ga 48 x 96, 10 sheets" }

    it "resolves the taught 16 ga stainless line to 0.0625 in with nothing left to ask" do
      r = described_class.parse(line, buyer_terms: [taught])
      expect(r["thickness_in"]).to eq(0.0625)
      expect(r["material"]).to eq("stainless steel")
      expect(r["form"]).to eq("sheet")
      expect(r["width_in"]).to eq(48)
      expect(r["length_in"]).to eq(96)
      expect(r["quantity"]).to eq(10)
      expect(r.evidence["thickness_in"]["text"]).to eq("16 ga")
      expect(r.conflicts).to be_empty
      expect(r.unknowns).to be_empty
      expect(r.rules_used).to include("Buyer profile: \"16 ga\" means thickness 0.0625 (taught by the rep)")
    end

    it "shows the taught source on the thickness field" do
      r = described_class.parse(line, buyer_terms: [taught])
      expect(r.evidence["thickness_in"]["explanation"]).to eq("Read as thickness 0.0625 in, as the rep taught on RFQ-0001")
    end

    ["0.060 in thick", "0.060 in", "0.060 x 48 x 96"].each do |dimension|
      it "keeps a conflict when taught gauge accompanies explicit #{dimension}" do
        r = described_class.parse("304 SS sheet 16 ga #{dimension}, 10 sheets", buyer_terms: [taught])
        expect(r["thickness_in"]).to be_nil
        expect(r.conflicts.map { |c| c["code"] }).to include("gauge_vs_decimal")
        expect(r.unknowns.map { |u| u["field"] }).to include("thickness_in")
        expect(r.evidence["thickness_in"]["text"]).to include("0.060")
      end
    end

    it "retains learned provenance as well as taught provenance" do
      learned = taught.merge("source" => "learned")
      r = described_class.parse(line, buyer_terms: [learned])
      expect(r.evidence["thickness_in"]["explanation"]).to eq("Read as thickness 0.0625 in, as you confirmed on RFQ-0001")
      expect(r.rules_used).to include("Gauge table: stainless steel, 16 ga = 0.0625 in")
    end

    it "uses the same buyer's taught decimal on the final second RFQ and keeps other buyers held" do
      text = "Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets"
      term = taught.merge("term" => "0.060 in", "meaning" => { "fields" => { "gauge" => 16, "thickness" => 0.0625 } })
      learned = described_class.parse(text, buyer_terms: [term])
      expect(learned["thickness_in"]).to eq(0.0625)
      expect(learned.evidence["thickness_in"]["text"]).to eq("0.060 in")
      expect(learned.evidence["thickness_in"]["explanation"]).to include("as the rep taught on RFQ-0001")
      expect(RfqProcessing::Readiness.decide(learned, match: { "status" => "exact" }).state).to eq("ready")
      other_buyer = described_class.parse(text)
      expect(other_buyer["thickness_in"]).to eq(0.060)
      expect(RfqProcessing::Readiness.decide(other_buyer, match: { "status" => "exact" }).state).to eq("needs_buyer")
    end

  end
end
