# frozen_string_literal: true

RSpec.describe RfqProcessing::Pipeline do
  let(:pipeline) { described_class.new(llm: false) }
  let(:demo_dir) { File.expand_path("../../../../docs/product/demo_rfq", __dir__) }

  it "ignores attachment headers, shipping details and follow-up prose" do
    first = pipeline.process(content: File.read(File.join(demo_dir, "email.txt")), type: "email")
    second = pipeline.process(content: File.read(File.join(demo_dir, "second_rfq_email.txt")), type: "email")
    expect(first["lines"].size).to eq(8)
    expect(second["lines"].size).to eq(1)
    expect(first["lines"][3].values_at("quantity", "quantity_unit")).to eq([2000, "lb"])
  end

  it "keeps the PDF schedule and total demand instead of packaging and boilerplate" do
    result = pipeline.process(content: File.binread(File.join(demo_dir, "northline_rfq_2026-1010.pdf")), type: "pdf")
    expect(result["lines"].size).to eq(8)
    expect(result["lines"][3].values_at("quantity", "quantity_unit")).to eq([2000, "lb"])
    expect(result["lines"][0]["evidence"]["material"]["location"]).to start_with("page 1")
  end
  it "keeps newline-separated global requirement scopes distinct in email" do
    text = "MTRs required on all steel\nCOA required on all abrasives\nSteel plate 1/2 48x96 2 plates\nGlass bead 100 lb"
    result = pipeline.process(content: text, type: "email")
    expect(result["lines"].size).to eq(2)
    steel, glass = result["lines"]
    expect(steel["compliance"].map { |entry| entry["label"] }).to eq(["Mill test report required"])
    expect(glass["compliance"].map { |entry| entry["label"] }).to eq(["Certificate of analysis (COA) required"])
    expect(steel.dig("processing", "rfq_body")).to eq("MTRs required on all steel\nCOA required on all abrasives")
  end

end
