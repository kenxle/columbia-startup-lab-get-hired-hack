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
end
