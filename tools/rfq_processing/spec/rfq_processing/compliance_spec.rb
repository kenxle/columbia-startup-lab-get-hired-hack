# frozen_string_literal: true

# Worked examples T17 to T25 come from Ken's domain research, section 6
# (docs/research/20261010.01_rfq_sharper_angle/research_domain_rules.md).
RSpec.describe RfqProcessing::Compliance do
  def flag(flags, requirement)
    flags.find { |f| f["requirement"] == requirement }
  end

  describe "T17: ASME code material with a 3.1 cert" do
    let(:flags) do
      described_class.flags(
        text: "SA-240 316L 3/8 plt 60x120 x2 w/ 3.1 cert",
        spec: { "material" => "stainless steel", "grade" => "316L", "form" => "plate", "standard" => "SA-240" }
      )
    end

    it "flags ASME SA as stated with the exact spec text as evidence" do
      expect(flag(flags, "asme_sa")).to include("trigger" => "stated", "evidence" => "SA-240", "label" => "ASME SA code material")
    end

    it "flags the 3.1 certificate as stated with the bare token as evidence" do
      expect(flag(flags, "en10204_3_1")).to include("trigger" => "stated", "evidence" => "3.1")
    end

    it "flags one MTR, stated from the cert word, and mentions the implying spec in the note" do
      mtrs = flags.select { |f| f["requirement"] == "mtr" }
      expect(mtrs.size).to eq(1)
      expect(mtrs.first).to include("trigger" => "stated", "evidence" => "cert")
      expect(mtrs.first["note"]).to include("SA-240")
    end

    it "returns string-keyed hashes with the five fields, stated flags first in line order" do
      expect(flags.map(&:keys)).to all(eq(%w[requirement label evidence trigger note]))
      expect(flags.map { |f| f["requirement"] }).to eq(%w[asme_sa en10204_3_1 mtr])
    end
  end

  describe "T18: pipe with PMI" do
    let(:flags) { described_class.flags(text: "2in sch40 304/304L A312 smls 20ft x30 PMI", spec: { "standard" => "A312" }) }

    it "flags PMI as stated" do
      expect(flag(flags, "pmi")).to include("trigger" => "stated", "evidence" => "PMI")
    end

    it "implies an MTR from A312 and says the scope was not verified" do
      expect(flag(flags, "mtr")).to include("trigger" => "implied", "evidence" => "A312")
      expect(flag(flags, "mtr")["note"]).to include("not verified")
    end

    it "does not read the dual grade 304/304L as a cert request" do
      expect(flags.map { |f| f["requirement"] }).to contain_exactly("pmi", "mtr")
    end
  end

  describe "T20: DFARS stated" do
    let(:flags) do
      described_class.flags(
        text: "304 plate 1/4 48x96 A240 DFARS compliant melted USA 3.1 x3",
        spec: { "material" => "stainless steel", "grade" => "304", "standard" => "A240" }
      )
    end

    it "flags DFARS from the keyword" do
      expect(flag(flags, "dfars")).to include("trigger" => "stated", "evidence" => "DFARS")
    end

    it "flags melt origin from the melt wording" do
      expect(flag(flags, "origin")).to include("trigger" => "stated", "evidence" => "melted USA")
    end

    it "flags the 3.1 certificate" do
      expect(flag(flags, "en10204_3_1")).to include("trigger" => "stated", "evidence" => "3.1")
    end

    it "lists the 3.1 flag before the MTR flag it derives from" do
      order = flags.map { |f| f["requirement"] }
      expect(order.index("en10204_3_1")).to be < order.index("mtr")
    end
  end

  describe "T21: DFARS implied by context, no keyword in the line" do
    let(:flags) do
      described_class.flags(
        text: "304 rd bar 2in A276 12ft x10",
        spec: { "material" => "stainless steel", "grade" => "304", "form" => "round bar", "standard" => "A276" },
        context: { ship_to_defense: true, dpas_rating: "DO-A1" }
      )
    end

    it "flags DFARS with trigger context and the context as evidence" do
      expect(flags.size).to eq(1)
      expect(flags.first).to include("requirement" => "dfars", "trigger" => "context", "evidence" => "defense ship-to, DPAS DO-A1")
    end

    it "says the inference is medium confidence and mentions the DPAS acceptance deadline" do
      expect(flags.first["note"]).to include("Medium confidence").and include("15 working days")
    end

    it "does not flag DFARS for a defense ship-to when the material is not a specialty metal" do
      carbon = described_class.flags(text: "A36 plate 1/2 48x96", spec: { "material" => "carbon steel" }, context: { ship_to_defense: true })
      expect(carbon).to eq([])
    end
  end

  describe "T22: Buy America with a coating step" do
    let(:text) { "L3x3x1/4 x 20' A36 galv x40 Buy America state DOT bridge" }

    it "flags Buy America as stated" do
      expect(flag(described_class.flags(text: text), "buy_america")).to include("trigger" => "stated", "evidence" => "Buy America")
    end

    it "keeps one Buy America flag when the funding context also points at it" do
      flags = described_class.flags(text: text, context: { funding: "state DOT bridge" })
      buy = flags.select { |f| f["requirement"] == "buy_america" }
      expect(buy.size).to eq(1)
      expect(buy.first["trigger"]).to eq("stated")
      expect(buy.first["note"]).to include("state DOT bridge")
    end

    it "flags Buy America from funding context alone when the line says nothing" do
      flags = described_class.flags(text: "L3x3x1/4 x 20' A36 galv x40", context: { funding: "state DOT bridge" })
      expect(flag(flags, "buy_america")).to include("trigger" => "context", "evidence" => "funding: state DOT bridge")
    end
  end

  describe "T23: sour service" do
    it "flags NACE as stated with the standard name as evidence" do
      flags = described_class.flags(text: "1/2 A516-70 plate 72x120 NACE MR0175 HIC tested x2")
      expect(flag(flags, "nace")).to include("trigger" => "stated", "evidence" => "NACE MR0175")
      expect(flag(flags, "nace")["note"]).to include("22 HRC")
    end
  end

  describe "T24: export-controlled attachment" do
    let(:flags) do
      described_class.flags(
        text: "6061-T651 plate 2 x 12 x 24 x4",
        spec: { "material" => "aluminum", "grade" => "6061-T651" },
        context: { attachment_markings: ["ITAR controlled technical data"] }
      )
    end

    it "flags ITAR from the attachment marking with trigger context" do
      expect(flags.size).to eq(1)
      expect(flags.first).to include("requirement" => "itar", "trigger" => "context", "evidence" => "attachment marked \"ITAR controlled technical data\"")
    end

    it "says the confidence is low and to flag, not interpret" do
      expect(flags.first["note"]).to include("low").and include("do not interpret")
    end
  end

  describe "T25: A500 tube, negative control" do
    let(:flags) { described_class.flags(text: "1-1/2 sq tube A500 C 11ga 24ft x8", spec: { "material" => "carbon steel", "form" => "square tube", "standard" => "A500" }) }

    it "implies an informational MTR from the A500 spec and nothing else" do
      expect(flags.size).to eq(1)
      expect(flags.first).to include("requirement" => "mtr", "trigger" => "implied", "evidence" => "A500")
      expect(flags.first["note"]).to include("informational")
    end
  end

  describe "lines with no triggers" do
    it "returns an empty array for a plain line" do
      expect(described_class.flags(text: "304 SS sheet 16ga 4x8")).to eq([])
    end

    it "does not read 3.125 or 13.1 as a 3.1 cert" do
      expect(described_class.flags(text: "3.125 plate 48x96 x2 13.1 long")).to eq([])
    end

    it "handles nil text and missing spec and context" do
      expect(described_class.flags(text: nil, spec: nil, context: nil)).to eq([])
    end
  end

  describe "keyword matching" do
    it "is case-insensitive but keeps the original substring as evidence" do
      flags = described_class.flags(text: "a36 angle dfars compliant w/ Mill Certs")
      expect(flag(flags, "dfars")["evidence"]).to eq("dfars")
      expect(flag(flags, "mtr")["evidence"]).to eq("Mill Certs")
    end

    it "counts certificate once and does not treat dual certified as a cert request" do
      expect(flag(described_class.flags(text: "316L bar w/ certificate"), "mtr")["evidence"]).to eq("certificate")
      expect(described_class.flags(text: "304/304L dual certified sheet")).to eq([])
    end

    it "reads Domestic only as an origin flag, not Buy America" do
      flags = described_class.flags(text: "A36 plate 1/2 48x96 Domestic only")
      expect(flags.map { |f| f["requirement"] }).to eq(["origin"])
      expect(flags.first["evidence"]).to eq("Domestic only")
    end

    it "reads a bare domestic as Buy America and says it is a question, not a guess" do
      flags = described_class.flags(text: "A36 plate 1/2 48x96 domestic")
      expect(flag(flags, "buy_america")).to include("evidence" => "domestic")
      expect(flag(flags, "buy_america")["note"]).to include("not a guess")
    end

    it "reads EN 10204 3.2 witnessed as one 3.2 flag and no 3.1 flag" do
      flags = described_class.flags(text: "316L bar EN 10204 3.2 witnessed")
      expect(flags.map { |f| f["requirement"] }).to eq(["en10204_3_2"])
      expect(flags.first["evidence"]).to eq("EN 10204 3.2")
    end

    it "asks which type when EN 10204 is named without one" do
      flags = described_class.flags(text: "316L bar EN 10204")
      expect(flag(flags, "en10204_3_1")).to include("evidence" => "EN 10204")
      expect(flag(flags, "en10204_3_1")["note"]).to include("without a certificate type")
    end

    it "notes the DFARS angle when melt wording appears without a DFARS keyword" do
      flags = described_class.flags(text: "A36 plate melted in USA")
      expect(flags.map { |f| f["requirement"] }).to eq(["origin"])
      expect(flags.first["note"]).to include("DFARS")
    end
  end

  describe "implied and context triggers" do
    it "treats an AMS standard as aerospace: ask for certs and origin, low confidence" do
      flags = described_class.flags(text: "AMS 5643 bar 1in x 12ft", spec: { "standard" => "AMS 5643" })
      expect(flags.map { |f| [f["requirement"], f["trigger"], f["evidence"]] }).to eq([["mtr", "implied", "AMS 5643"], ["origin", "implied", "AMS 5643"]])
      expect(flags.first["note"]).to include("low")
    end

    it "flags ASME SA from a pressure vessel buyer with trigger context" do
      flags = described_class.flags(text: "316L plate 1/2 48x96", spec: { "material" => "stainless steel" }, context: { buyer_type: "pressure vessel fabricator" })
      expect(flag(flags, "asme_sa")).to include("trigger" => "context", "evidence" => "buyer: pressure vessel fabricator")
    end

    it "orders stated, then implied, then context" do
      flags = described_class.flags(
        text: "A312 pipe w/ PMI",
        spec: { "material" => "stainless steel", "standard" => "A312" },
        context: { buyer_type: "boiler shop" }
      )
      expect(flags.map { |f| f["trigger"] }).to eq(%w[stated implied context])
    end
  end

  describe "RudCo paperwork: COA, REACH, RoHS (Ken, 13:00)" do
    it "flags a certificate of analysis without also flagging an MTR" do
      flags = described_class.flags(text: "Steel shot S-330, 2,000 lb, COA with each lot")
      expect(flags.map { |f| f["requirement"] }).to eq(["coa"])
      expect(flags.first["evidence"]).to eq("COA")
    end

    it "flags the long form too" do
      flags = described_class.flags(text: "P1020 ingot 5000 lb, certificate of analysis required")
      expect(flags.map { |f| f["requirement"] }).to eq(["coa"])
    end

    it "flags REACH and RoHS, and ignores the verb reach" do
      flags = described_class.flags(text: "Glass bead 10 bags, REACH and RoHS statements please; we need it to reach us by Friday")
      expect(flags.map { |f| f["requirement"] }).to contain_exactly("reach", "rohs")
      expect(flags.find { |f| f["requirement"] == "reach" }["evidence"]).to eq("REACH")
    end
  end
  it "retains only exact requirement sentences for a later buyer-answer rerun" do
    body = "Hello purchasing. MTRs required on all steel. Deliver tomorrow. Send a COA with each lot of abrasive."
    expect(described_class.requirement_text(body)).to eq("MTRs required on all steel.\nSend a COA with each lot of abrasive.")
    expect(described_class.requirement_text(nil)).to eq("")
  end

  describe "product scope in RFQ body requirements" do
    let(:body) { "MTRs required on all steel. Send a COA with each lot of abrasive. DFARS required on all items." }

    it "applies the steel request to steel without copying abrasive paperwork" do
      flags = described_class.flags(text: "304 sheet", spec: { "material" => "stainless steel" }, body_text: body)
      expect(flags.map { |entry| entry["requirement"] }).to contain_exactly("mtr", "dfars")
      expect(flag(flags, "mtr")["evidence"]).to eq("MTRs")
      expect(flag(flags, "mtr")["note"]).to include("MTRs required on all steel.")
    end

    it "scopes separate requests joined by comma and send" do
      body = "MTRs required on all steel, and send a COA with each lot of abrasive."
      steel = described_class.flags(text: "304 sheet", spec: { "material" => "stainless steel" }, body_text: body)
      glass = described_class.flags(text: "Glass bead", spec: { "material" => "glass", "form" => "bead" }, body_text: body)
      expect(steel.map { |entry| entry["requirement"] }).to eq(["mtr"])
      expect(glass.map { |entry| entry["requirement"] }).to eq(["coa"])
    end

    it "re-evaluates body scope from a buyer's current material instead of the original wording" do
      flags = described_class.flags(text: "steel sheet", spec: { "material" => "aluminum", "form" => "sheet" }, body_text: "MTRs required on all steel.")
      expect(flags).to be_empty
      explicit = described_class.flags(text: "steel sheet MTR required", spec: { "material" => "aluminum", "form" => "sheet" }, body_text: "MTRs required on all steel.")
      expect(explicit.map { |entry| entry["requirement"] }).to eq(["mtr"])
    end

    it "re-evaluates abrasive scope from the current form and keeps fallback for missing fields" do
      changed = described_class.flags(text: "Steel shot", spec: { "material" => "carbon steel", "form" => "sheet" }, body_text: "COA with each lot of abrasive.")
      expect(changed).to be_empty
      fallback = described_class.flags(text: "Steel shot", body_text: "MTRs required on all steel. COA with each lot of abrasive.")
      expect(fallback.map { |entry| entry["requirement"] }).to contain_exactly("mtr", "coa")
    end

    it "does not apply steel or abrasive requests to aluminum" do
      flags = described_class.flags(text: "P1020 aluminum ingot", spec: { "material" => "aluminum" }, body_text: body)
      expect(flags.map { |entry| entry["requirement"] }).to eq(["dfars"])
    end

    it "applies abrasive COA and literal all-steel MTR to steel shot" do
      flags = described_class.flags(text: "Steel shot S-330", spec: { "material" => "carbon steel", "form" => "shot" }, body_text: body)
      expect(flags.map { |entry| entry["requirement"] }).to contain_exactly("coa", "mtr", "dfars")
      expect(flag(flags, "coa")["evidence"]).to eq("COA")
      expect(flag(flags, "coa")["note"]).to include("Send a COA with each lot of abrasive.")
    end

    it "keeps explicitly requested line paperwork even outside a body's family scope" do
      flags = described_class.flags(text: "Aluminum ingot COA MTR required", spec: { "material" => "aluminum" }, body_text: body)
      expect(flags.map { |entry| entry["requirement"] }).to contain_exactly("coa", "mtr", "dfars")
      expect(flag(flags, "coa")["evidence"]).to eq("COA")
    end

    it "does not call a glass abrasive steel" do
      flags = described_class.flags(text: "Glass bead 10 bags", spec: { "material" => "glass", "form" => "bead" }, body_text: body)
      expect(flags.map { |entry| entry["requirement"] }).to contain_exactly("coa", "dfars")
    end
  end

end
