# frozen_string_literal: true

RSpec.describe "spelled-number item selection" do
  let(:pipeline) { RfqProcessing::Pipeline.new(llm: false, jev: false) }
  let(:request) { "twenty sheets of stainless 304, sixteen gauge, four by eight, brushed finish" }

  it "keeps Hirsh's exact item visible and held without inventing numeric fields" do
    result = pipeline.process(content: request, type: "email")
    expect(result["lines"].size).to eq(1)
    line = result["lines"].first
    expect(line["original_text"]).to eq(request)
    expect(line["state"]).to eq("needs_buyer")
    expect(line["quantity"]).to be_nil
    expect(line.dig("spec", "thickness")).to be_nil
    expect(line["unit_price"]).to be_nil
    expect(line["unresolved_fields"]).to include("quantity", "thickness")
  end

  ["twenty sheets of stainless steel with brushed finish and mill paperwork",
   "stainless steel sheet sixteen gauge with brushed finish for the workshop",
   "stainless steel sheet four by eight with brushed finish for the workshop."] .each do |text|
    it "admits the physical item signature in #{text.inspect}" do
      expect(pipeline.item_line?(text)).to be(true)
    end
  end

  ["Twenty sheets of stainless steel with brushed finish and mill paperwork",
   "TWENTY SHEETS OF STAINLESS STEEL WITH BRUSHED FINISH AND MILL PAPERWORK"].each do |text|
    it "keeps title/uppercase spelled quantities visible without inventing values: #{text}" do
      lines = pipeline.process(content: text, type: "email")["lines"]
      expect(lines.size).to eq(1)
      expect(lines.first).to include("original_text" => text, "state" => "needs_buyer", "quantity" => nil, "unit_price" => nil)
      expect(lines.first["unresolved_fields"]).to include("quantity")
    end
  end

  ["Please send twenty copies of the paperwork for our stainless steel order.",
   "MTRs required on all steel, twenty sheets discussed in our earlier email.",
   "Please tell us whether the shipment can arrive before Friday this week.",
   "twenty pounds of unspecified goods requested for our next delivery to the workshop"].each do |text|
    it "does not broaden selection to prose or compliance: #{text.inspect}" do
      expect(pipeline.item_line?(text)).to be(false)
    end
  end

  it "keeps email headers out even when they contain the complete item wording" do
    result = pipeline.process(content: "Subject: #{request}\n#{request}", type: "email")
    expect(result["lines"].map { |line| line["original_text"] }).to eq([request])
  end
end
