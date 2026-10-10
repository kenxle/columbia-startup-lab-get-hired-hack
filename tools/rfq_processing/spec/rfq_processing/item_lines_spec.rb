# frozen_string_literal: true

RSpec.describe RfqProcessing::ItemLines do
  def pdf_lines(text)
    lines = text.lines.each_with_index.filter_map do |raw, index|
      next if raw.strip.empty?
      RfqProcessing::Extractor::Line.new(text: raw.strip, layout_text: raw.rstrip, location: "page 2, line #{index + 1}")
    end
    RfqProcessing::Extractor::Extraction.new(lines: lines, source_type: "pdf", warnings: [])
  end

  it "assembles wrapped schedule descriptions without making the packaging a second item" do
    extraction = pdf_lines(<<~TEXT)
      Tender value estimated at R50 000 000 including tax
      Item  Description                         Unit   Quantity  Rate
      12    STEEL SHOT; TYPE: S 280               KG     25 000
            MATERIAL: CAST STEEL; HRC 40-50
            CONTAINER SIZE: 500 KG PER BOX
      13    Aluminium ingot P1020                KG     8 000
            Packaging: 25 KG PER BAG
                         TOTAL PRICE:
      Delivery Lead-Time: 15 days
    TEXT
    items = described_class.pdf(extraction)
    expect(items.size).to eq(2)
    expect(items.first.text).to include("S 280", "25 000", "MATERIAL: CAST STEEL", "500 KG PER BOX")
    expect(items.first.location).to eq("page 2, lines 3-5")
    expect(items.last.text).to include("P1020", "8 000", "25 KG PER BAG")
    expect(items.map(&:text).join).not_to include("R50", "TOTAL", "Delivery")
  end

  it "accepts quantity before unit and an unfamiliar product in a typed table" do
    extraction = pdf_lines("Item  Description           Quantity  Unit\n1     Ceramic washers       250       EA\n")
    expect(described_class.pdf(extraction).map(&:text)).to eq(["1     Ceramic washers       250       EA"])
  end

  it "keeps a quantity-less item held without promoting packaging or monetary thresholds to demand" do
    extraction = pdf_lines(<<~TEXT)
      Item  Description                         Unit   Quantity
      12    STEEL SHOT; CONTAINER SIZE: 1000 KG PER BOX
      80/20 system for requirements with a Rand value up to R50 000 000
      Page 35 of 35
    TEXT
    items = described_class.pdf(extraction)
    expect(items.size).to eq(1)
    expect(RfqProcessing::RulesParser.parse(items.first.text).fields["quantity"]).to be_nil
    expect(extraction.warnings.join).to include("no recognized demand quantity")
    expect(items.first.text).not_to include("R50", "Page 35")
  end

  it "requires physical product evidence in an untabulated PDF" do
    extraction = pdf_lines(<<~TEXT)
      Page 17 of 35
      1.2 This bid does not exceed R50 000 000
      Please submit bids before 17:00
      STEEL SHOT S-330 2,000 lb
      304 stainless sheet 16ga 4x8 20 sheets
      STEEL SHOT CONTAINER SIZE: 1000 KG PER BOX
    TEXT
    expect(described_class.pdf(extraction).map(&:text)).to eq(["STEEL SHOT S-330 2,000 lb", "304 stainless sheet 16ga 4x8 20 sheets"])
    expect(extraction.warnings.join).to include("review the source for omitted or wrapped items")
  end

  it "keeps page boundaries and warns when a row may continue onto another page" do
    extraction = pdf_lines("Item  Description  Unit  Quantity\n1     Steel shot   KG    500\n")
    next_page = pdf_lines("Item  Description  Unit  Quantity\n2     Aluminium ingot   KG    250\nTOTAL PRICE:\n")
    next_page.lines.each { |line| line.location = line.location.sub("page 2", "page 3") }
    extraction.lines.concat(next_page.lines)
    items = described_class.pdf(extraction)
    expect(items.size).to eq(2)
    expect(items.first.location).to start_with("page 2,")
    expect(items.last.location).to start_with("page 3,")
    expect(extraction.warnings.join).to include("end of page 2", "continuation")
  end

  it "stops at a new section rather than appending its numbered prose" do
    extraction = pdf_lines("Item  Description  Unit  Quantity\n1     Steel shot   KG    500\n  SECTION 5\n  12.3 All bidders agree to the following conditions\n")
    expect(described_class.pdf(extraction).first.text).to eq("1     Steel shot   KG    500")
  end

  it "retains all eight rows of the compact demo including the unmatched screw" do
    source = File.expand_path("../../../../docs/product/demo_rfq/northline_rfq_2026-1010.pdf", __dir__)
    extraction = RfqProcessing::Extractor.extract(File.binread(source), type: "pdf")
    items = described_class.pdf(extraction)
    expect(items.size).to eq(8)
    expect(items[2].text).to include("3.1 cert")
    expect(items[3].text).to include("50 lb bags", "2000", "COA")
    expect(items.last.text).to include("hex cap screws", "500")
    expect(items.map(&:location)).to all(start_with("page 1,"))
  end

  it "carries standalone body requests without carrying another row's paperwork" do
    extraction = pdf_lines("MTRs required on all steel. Send a COA with each lot of abrasive.\nItem  Description  Unit  Quantity\n1     Steel shot COA with each lot   KG    500\n")
    expect(described_class.body_text(extraction)).to eq("MTRs required on all steel. Send a COA with each lot of abrasive.")
  end

  it "removes explicit Line identifiers before a fraction but preserves item identifiers" do
    extraction = pdf_lines("Line Description                      Quantity  Unit\n7    1/2 A36 plate 5x10                3         plates\n")
    item = described_class.pdf(extraction).first
    expect(item.text).to start_with("1/2 A36")
    reading = RfqProcessing::RulesParser.parse(item.text)
    expect(reading.fields["thickness_in"]).to eq(0.5)
    expect(reading.fields["quantity"]).to eq(3)
    expect(item.location).to eq("page 2, line 2")
  end

  it "keeps a wrapped per-row MTR out of global PDF body requirements" do
    extraction = pdf_lines(<<~TEXT)
      DFARS required on all items.
      Line Description            Quantity  Unit
      1    Steel plate            2         plates
           MTR required
      2    Aluminum ingot         500       lb
      TOTAL PRICE:
    TEXT
    items = described_class.pdf(extraction)
    expect(items.size).to eq(2)
    expect(items.first.text).to include("MTR required")
    body = described_class.body_text(extraction)
    expect(body).to eq("DFARS required on all items.")
    expect(extraction.warnings).to be_empty
    flags = RfqProcessing::Compliance.flags(text: items.last.text, spec: { "material" => "aluminum" }, body_text: body)
    expect(flags.map { |entry| entry["requirement"] }).to eq(["dfars"])
  end

  it "retains an incomplete middle row and continues to the next complete row" do
    extraction = pdf_lines(<<~TEXT)
      Line Description             Quantity  Unit
      1    Steel shot S-330        500       lb
      2    Steel shot S-390                  lb
      3    Steel shot S-550        100       lb
      TOTAL PRICE:
    TEXT
    items = described_class.pdf(extraction)
    expect(items.size).to eq(3)
    expect(items.map { |item| RfqProcessing::RulesParser.parse(item.text).fields["quantity"] }).to eq([500, nil, 100])
    result = RfqProcessing::Pipeline.new(llm: false).process_line(items[1], position: 2)
    expect(result["state"]).not_to eq("ready")
    expect(result["quantity"]).to be_nil
    expect(extraction.warnings.join).to include("page 2, line 3", "no recognized demand quantity")
  end

  it "preserves newline-separated family scopes in PDF body text" do
    extraction = pdf_lines(<<~TEXT)
      MTRs required on all steel
      COA required on all abrasives
      Line Description             Quantity  Unit
      1    Steel plate             2         plates
      2    Glass bead              100       lb
      TOTAL PRICE:
    TEXT
    body = described_class.body_text(extraction)
    expect(body).to eq("MTRs required on all steel\nCOA required on all abrasives")
    steel = RfqProcessing::Compliance.flags(text: "Steel plate", spec: { "material" => "carbon steel", "form" => "plate" }, body_text: body)
    glass = RfqProcessing::Compliance.flags(text: "Glass bead", spec: { "material" => "glass", "form" => "bead" }, body_text: body)
    expect(steel.map { |entry| entry["requirement"] }).to eq(["mtr"])
    expect(glass.map { |entry| entry["requirement"] }).to eq(["coa"])
  end

  it "reads the unchanged real 35-page RFQ as one demand with full specification and page evidence" do
    source = File.expand_path("../../../../docs/example_rfqs/transnet-steel-shot-2024/source.pdf", __dir__)
    extraction = RfqProcessing::Extractor.extract(File.binread(source), type: "pdf")
    expect(extraction.pages).to eq(35)
    expect(extraction.warnings).to be_empty
    items = described_class.pdf(extraction)
    expect(items.size).to eq(1)
    item = items.first
    expect(item.location).to match(/\Apage 17, lines \d+-\d+\z/)
    expect(item.text).to include("006828999", "STEEL SHOT", "S 390", "HRC 40-50", "1.2 MM", "1000 KG PER BOX")
    expect(item.text).to match(/KG\s+50 000/)
    expect(item.text).not_to include("R50", "VAT", "TOTAL PRICE")
  end
end
