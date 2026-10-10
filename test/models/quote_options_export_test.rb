require "test_helper"
require "csv"
require "pdf/reader"

class QuoteOptionsExportTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "options-export")
    @line = @quote.quote_lines.second
    @options = [option("a", "Option A: Standard plate", "5.25"), option("b", "Option B: Alternate plate", nil)]
    @line.update!(processing: {"alternates" => @options}, notes: "PRIVATE-OPTION-NOTE")
    @quote.approve!
  end

  def option(id, label, price)
    {"id" => id, "label" => label, "catalog_sku" => "PLATE-#{id}", "spec" => {"grade" => "A36", "thickness" => "0.25 in"},
      "unit_price" => price, "currency" => "USD", "price_source" => "Supplier plate listing https://example.test/#{id}",
      "benchmark" => {"name" => "Supplier reference #{id}", "as_of" => "2026-10-10", "kind" => "list_price", "unit" => @line.quantity_unit},
      "lead_time" => {"text" => "3 days", "source" => "Supplier stated timing"}, "unresolved_fields" => price ? [] : ["unit_price"]}
  end

  def outputs
    {
      email: QuoteWorkspace::FinalQuote.new(@quote).body,
      pdf: PDF::Reader.new(StringIO.new(QuoteWorkspace::PdfExport.new(@quote).to_pdf)).pages.map(&:text).join("\n"),
      csv: QuoteWorkspace::CsvExport.new(@quote).to_csv
    }
  end

  test "approved exports distinguish priced mutually exclusive options and preserve subtotal" do
    before = @quote.subtotal
    outputs.each do |format, content|
      assert_includes content, "Option A: Standard plate", format.to_s
      assert_includes content, "Option B: Alternate plate"
      assert_includes content, "Buyer choice"
      assert_includes content, "52.50"
      assert_includes content, "4640.00"
      assert_includes content, "Supplier plate listing"
      assert_includes content, "2026-10-10"
      assert_includes content, "3 days"
      assert_includes content, "Supplier stated timing"
      assert_includes content.downcase, "unpriced"
      refute_includes content, "PRIVATE-OPTION-NOTE"
    end
    assert_equal before, @quote.reload.subtotal
    assert_equal "needs_buyer", @line.reload.state
    refute @line.quotable?
    rows = CSV.parse(outputs[:csv])
    priced = rows.find { |row| row[1] == "Buyer choice option" }
    held = rows.find { |row| row[1] == "Held option, unpriced" }
    headers = QuoteWorkspace::CsvExport::COLUMN_HEADERS
    assert_equal "5.25", priced[headers.index("Unit price (USD)")]
    assert_equal "52.50", priced[headers.index("Line total (USD)")]
    assert_equal "", held[headers.index("Unit price (USD)")]
    assert_equal "", held[headers.index("Line total (USD)")]
    assert_equal headers.length, priced.length
    assert_equal headers.length, held.length
  end

  test "option CSV text is formula safe and excludes unrelated metadata" do
    @options.first["catalog_sku"] = "=HYPERLINK(1)"
    @options.first["spec"]["grade"] = "+A36"
    @options.first["price_source"] = "@supplier"
    @options.first["benchmark"]["name"] = "=reference"
    @options.first["lead_time"]["source"] = "-timing"
    @line.update!(processing: {"alternates" => @options, "private" => "PRIVATE-METADATA"})
    @quote.approve!
    csv = QuoteWorkspace::CsvExport.new(@quote).to_csv
    ["'=HYPERLINK(1)", "'+A36", "'@supplier", "'=reference", "'-timing"].each { |value| assert_includes csv, value }
    refute_includes csv, "PRIVATE-METADATA"
  end

  test "processing price basis and observation timestamp survive all exports" do
    stamp = "2026-10-10T17:04:39Z"
    basis = "USD per #{@line.quantity_unit}"
    @options.first["benchmark"].merge!("unit" => basis, "as_of" => stamp)
    @line.update!(processing: {"alternates" => @options})
    @quote.approve!
    before = @quote.subtotal
    outputs.each do |format, content|
      assert_includes content, "52.50", format.to_s
      assert_includes content, stamp, format.to_s
    end
    assert_equal before, @quote.reload.subtotal
    refute @line.reload.quotable?
  end

  test "stale approval prevents all option exports including a previously loaded CSV" do
    csv = QuoteWorkspace::CsvExport.new(@quote)
    Quote.find(@quote.id).invalidate_approval!
    assert_raises(QuoteWorkspace::CsvExport::NotApproved) { csv.to_csv }
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { QuoteWorkspace::FinalQuote.new(@quote).body }
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { QuoteWorkspace::PdfExport.new(@quote).to_pdf }
  end

  test "unpriced and malformed options never manufacture zero prices" do
    @options.first.delete("price_source")
    @line.update!(processing: {"alternates" => @options})
    @quote.approve!
    content = outputs
    content.each_value { |value| refute_includes value, "52.50" }
    refute_includes content[:email], "Status: Buyer choice"
    assert_includes content[:email], "Held lines are unpriced and excluded."
    @line.update!(processing: {"alternates" => [{"label" => "INVALID OPTION"}]})
    @quote.approve!
    outputs.each_value { |value| refute_includes value, "INVALID OPTION" }
  end

  test "PDF option text participates in glyph validation" do
    @options.first["label"] = "Option A: \u{10FFFF}"
    @line.update!(processing: {"alternates" => @options})
    @quote.approve!
    assert_raises(QuoteWorkspace::PdfExport::UnsupportedGlyph) { QuoteWorkspace::PdfExport.new(@quote).to_pdf }
  end
end
