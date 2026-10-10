# frozen_string_literal: true

RSpec.describe RfqProcessing::BuyerProfile do
  let(:terms) do
    [
      { "term" => "20 gate", "meaning" => { "fields" => { "gauge" => 20 } }, "source" => "taught", "client_name" => "Northline" },
      { "term" => "20G", "meaning" => { "fields" => { "gauge" => 20 } }, "source" => "learned", "client_name" => "Acme", "times_confirmed" => 3 },
      { "term" => "KB", "meaning" => { "fields" => { "finish" => "No. 4" } }, "source" => "taught", "client_name" => "Acme" }
    ]
  end

  it "reads one buyer's shorthand into the parser with the learned explanation" do
    r = RfqProcessing::RulesParser.parse("20 gate steel sheet 4x8 qty 5", buyer_terms: [terms[0]])
    expect(r["gauge"]).to eq(20)
    expect(r["thickness_in"]).to eq(0.0359)
    expect(r.evidence["gauge"]["text"]).to eq("20 gate")
    expect(r.evidence["gauge"]["explanation"]).to include("Northline (taught by the rep)")
    expect(r.rules_used.join).to include("Buyer profile")
  end

  it "reads another buyer's shorthand for the same thing" do
    r = RfqProcessing::RulesParser.parse("20G steel sheet 4x8 qty 5", buyer_terms: [terms[1], terms[2]])
    expect(r["gauge"]).to eq(20)
    expect(r.evidence["gauge"]["explanation"]).to include("learned from 3 approved requests")
  end

  it "does not fire on words the buyer never taught" do
    r = RfqProcessing::RulesParser.parse("20G steel sheet 4x8 qty 5", buyer_terms: [])
    expect(r["gauge"]).to be_nil
  end

  it "matches whole words only" do
    hits = described_class.apply([terms[2]], "KBX finish 304 sheet")
    expect(hits).to be_empty
    expect(described_class.apply([terms[2]], "304 sheet KB finish").size).to eq(1)
  end

  it "turns a rep edit into a term the app can save" do
    term = described_class.learn(evidence_text: "20 gate", field: "gauge", value: 20, client_name: "Northline")
    expect(term).to eq("term" => "20 gate", "meaning" => { "fields" => { "gauge" => 20 } }, "source" => "learned",
                       "client_name" => "Northline", "times_confirmed" => 1)
    expect(described_class.learn(evidence_text: "20", field: "gauge", value: 20)).to be_nil
    expect(described_class.learn(evidence_text: "the usual bolts", field: "part_number", value: "AN3-13A")["meaning"]).to eq("part_number" => "AN3-13A")
  end

  it "flows through the pipeline" do
    result = RfqProcessing.process(content: "20 gate stainless 304 sheet 4x8, 5 sheets", type: "email", catalog: [], buyer_terms: [terms[0]])
    line = result["lines"].first
    expect(line["spec"]["thickness"]).to eq(0.0375)
    expect(line["evidence"]["gauge"]["explanation"]).to include("taught by the rep")
  end

  describe "a term confirmed on an earlier RFQ (demo beat 8)" do
    let(:thickness_term) do
      { "term" => "16 ga", "meaning" => { "fields" => { "thickness" => 0.0625 } }, "source" => "learned", "client_name" => "Northline" }
    end
    let(:sheet) { "304 SS sheet 16 ga 48 x 96, 10 sheets" }

    it "names the RFQ a learned term was confirmed on, on the hit and on the parsed line" do
      learned = terms[1].merge("confirmed_on" => "RFQ-0001")
      hit = described_class.apply([learned], "20G steel sheet 4x8 qty 5").first
      expect(hit.confirmed_on).to eq("RFQ-0001")
      expect(hit.explanation).to eq("Read as gauge 20, as you confirmed on RFQ-0001")
      expect(hit.how).to eq("learned from 3 approved requests")

      r = RfqProcessing::RulesParser.parse("20G steel sheet 4x8 qty 5", buyer_terms: [learned])
      expect(r["gauge"]).to eq(20)
      expect(r.evidence["gauge"]["text"]).to eq("20G")
      expect(r.evidence["gauge"]["explanation"]).to eq("Read as gauge 20, as you confirmed on RFQ-0001")
    end

    it "names the RFQ a taught term was taught on" do
      taught = terms[0].merge("confirmed_on" => "RFQ-0001")
      hit = described_class.apply([taught], "20 gate steel sheet 4x8 qty 5").first
      expect(hit.explanation).to eq("Read as gauge 20, as the rep taught on RFQ-0001")
      expect(hit.how).to eq("taught by the rep")

      r = RfqProcessing::RulesParser.parse("20 gate steel sheet 4x8 qty 5", buyer_terms: [taught])
      expect(r["gauge"]).to eq(20)
      expect(r.evidence["gauge"]["explanation"]).to eq("Read as gauge 20, as the rep taught on RFQ-0001")
    end

    it "describes a thickness in inches" do
      hit = described_class.apply([thickness_term.merge("confirmed_on" => "RFQ-0001")], sheet).first
      expect(hit.fields).to eq("thickness_in" => 0.0625)
      expect(hit.explanation).to eq("Read as thickness 0.0625 in, as you confirmed on RFQ-0001")
      expect(hit.describe).to eq("thickness 0.0625")
    end

    it "keeps today's wording for a term without it" do
      taught = thickness_term.merge("source" => "taught")
      hit = described_class.apply([taught], sheet).first
      expect(hit.confirmed_on).to be_nil
      expect(hit.explanation).to eq("Northline (taught by the rep): \"16 ga\" means thickness 0.0625")
      expect(hit.to_h.keys).to include(:term, :match, :fields, :explanation, :describe, :how)

      blank = described_class.apply([taught.merge("confirmed_on" => " ")], sheet).first
      expect(blank.confirmed_on).to be_nil
      expect(blank.explanation).to eq("Northline (taught by the rep): \"16 ga\" means thickness 0.0625")
    end

    it "accepts symbol keys from the app" do
      hit = described_class.apply([{ term: "20G", meaning: { fields: { gauge: 20 } }, source: "learned", confirmed_on: "RFQ-0001" }],
                                  "20G steel sheet").first
      expect(hit.explanation).to eq("Read as gauge 20, as you confirmed on RFQ-0001")
    end

    it "round-trips confirmed_on through learn" do
      term = described_class.learn(evidence_text: "16 ga", field: "thickness_in", value: 0.0625, client_name: "Northline", confirmed_on: "RFQ-0001")
      expect(term).to eq("term" => "16 ga", "meaning" => { "fields" => { "thickness" => 0.0625 } }, "source" => "learned",
                         "client_name" => "Northline", "times_confirmed" => 1, "confirmed_on" => "RFQ-0001")
      expect(described_class.learn(evidence_text: "20 gate", field: "gauge", value: 20)).not_to have_key("confirmed_on")

      hit = described_class.apply([term], sheet).first
      expect(hit.explanation).to eq("Read as thickness 0.0625 in, as you confirmed on RFQ-0001")
    end
  end
end
