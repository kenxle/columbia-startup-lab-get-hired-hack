require "test_helper"
require "pdf/reader"

class PdfExportTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "pdf-export")
    @quote.approve!
    @export = QuoteWorkspace::PdfExport.new(@quote)
  end

  def reader
    PDF::Reader.new(StringIO.new(@export.to_pdf))
  end

  test "approved sample PDF includes quote details prices held questions and honest labels" do
    assert_equal "#{@quote.reference}-quote.pdf", @export.filename
    document = reader
    text = document.pages.map(&:text).join("\n")
    [ "RUDCO / QUOTE DESK", @quote.reference, "Approved:", "USD 4640.00", "USD 232.00", "LINE 1", "LINE 2", "LINE 3",
      "Unpriced. Excluded from subtotal.", "Sample price table", "2026-10-10", "Lead time: to confirm",
      "Mill test report" ].each { |value| assert_includes text, value }
    @quote.quote_lines.reject(&:quotable?).each do |line|
      assert_includes text.gsub(/\s+/, " "), line.clarification_question.gsub(/\s+/, " ")
    end
    assert document.pages.all? { |page| page.text.include?("RudCo Quote Desk") }
  end

  test "PDF refuses stale approvals and currently invalid lines" do
    @quote.quote_lines.load
    Quote.find(@quote.id).invalidate_approval!
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { @export.to_pdf }
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { @export.filename }
    @quote.reload.approve!
    @quote.quote_lines.first.update_columns(quantity: -1)
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { @export.to_pdf }
  end

  test "PDF omits notes raw uploads processing metadata and held pricing" do
    @quote.update!(source_text: "PRIVATE-FULL-RFQ", source_bytes: "PRIVATE-BYTES", original_filename: "PRIVATE-FILE.pdf",
      processing_revision: { "id" => "PRIVATE-REVISION" })
    @quote.quote_lines.second.update!(unit_price: "991.8765", catalog_sku: "PRIVATE-HELD-SKU", notes: "PRIVATE-NOTE", original_text: "PRIVATE-ORIGINAL")
    text = reader.pages.map(&:text).join
    %w[PRIVATE-FULL-RFQ PRIVATE-BYTES PRIVATE-FILE PRIVATE-REVISION 991.8765 PRIVATE-HELD-SKU PRIVATE-NOTE PRIVATE-ORIGINAL].each do |value|
      refute_includes text, value
    end
  end

  test "PDF preserves Unicode engineering specifications and precise unit prices" do
    line = @quote.quote_lines.first
    line.update!(spec: line.spec.merge("part_number" => "AN3-4A", "diameter" => "Ø ¼ in ±0.01", "thread" => "10-32 UNF", "grip" => "⅛ in", "drilling" => "Undrilled"),
      unit_price: "0.1234", quantity: "3", lead_time: "3 days", lead_time_source: "Supplier schedule")
    text = reader.pages.map(&:text).join("\n")
    [ "AN3-4A", "Ø ¼ in ±0.01", "10-32 UNF", "⅛ in", "Undrilled", "USD 0.1234", "USD 0.37", "Lead time: 3 days", "Supplier schedule" ].each do |value|
      assert_includes text, value
    end
  end

  test "unsupported glyph fails explicitly rather than corrupting a specification" do
    @quote.quote_lines.first.update!(description: "Unrenderable \u{10FFFF}")
    error = assert_raises(QuoteWorkspace::PdfExport::UnsupportedGlyph) { @export.to_pdf }
    assert_includes error.message, "U+10FFFF"
  end

  test "rep override never exports the old benchmark claim" do
    line = @quote.quote_lines.first
    line.update!(benchmark: { "name" => "OLD-MARKET-NAME", "as_of" => "2020-01-01", "explanation" => "OLD-CLAIM" })
    line.apply_manual_edit("unit_price" => "235")
    @quote.approve!
    text = reader.pages.map(&:text).join
    assert_includes text, "Rep-entered price"
    %w[OLD-MARKET-NAME 2020-01-01 OLD-CLAIM].each { |value| refute_includes text, value }
  end

  test "ready prices without benchmark evidence say it is not provided" do
    @quote.quote_lines.first.update!(benchmark: nil)
    assert_includes reader.pages.map(&:text).join, "Benchmark: not provided"
  end

  test "long multi-page quotes wrap every line and repeat brand page numbers and reference" do
    template = @quote.quote_lines.first.attributes.except("id", "created_at", "updated_at", "quote_id")
    12.times do |index|
      @quote.quote_lines.create!(template.merge("position" => index + 4, "description" => "Long line #{index + 4}: " + "industrial sheet specification " * 12))
    end
    document = reader
    assert_operator document.page_count, :>, 2
    text = document.pages.map(&:text).join("\n")
    (1..15).each { |position| assert_includes text, "LINE #{position} /" }
    document.pages.each_with_index do |page, index|
      assert_includes page.text, "RudCo Quote Desk"
      assert_includes page.text, @quote.reference
      assert_includes page.text, "Page #{index + 1} of #{document.page_count}"
    end
  end

  test "generating PDF leaves approval revision and rows unchanged" do
    before_quote = @quote.attributes
    before_lines = @quote.quote_lines.map(&:attributes)
    @export.to_pdf
    assert_equal before_quote, @quote.reload.attributes
    assert_equal before_lines, @quote.quote_lines.map(&:attributes)
  end
end
