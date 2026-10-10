require "test_helper"

class QuoteWorkspaceFlowTest < ActionDispatch::IntegrationTest
  def quote_id_from_redirect(browser_session = self)
    location = browser_session.response.location
    assert location, "expected a redirect"
    Integer(location[%r{/quotes/(\d+)}, 1])
  end

  def create_demo_quote(browser_session = self)
    browser_session.post demo_quotes_path
    assert_equal 302, browser_session.response.status
    Quote.find(quote_id_from_redirect(browser_session))
  end

  def upload(content, filename, content_type = "application/pdf")
    Rack::Test::UploadedFile.new(StringIO.new(content), content_type, true, original_filename: filename)
  end

  test "root and quote list respond" do
    get root_path
    assert_response :success

    get quotes_path
    assert_response :success
  end

  test "demo creates a sample quote for this session and shows it" do
    assert_difference "Quote.count", 1 do
      post demo_quotes_path
    end
    quote = Quote.find(quote_id_from_redirect)
    assert_redirected_to quote_path(quote)
    assert quote.sample_data?
    assert_equal BigDecimal("4640.00"), quote.subtotal

    follow_redirect!
    assert_response :success
    assert_includes response.body, "RFQ example created. Review the quote lines."
    refute_includes response.body, "Catalog items and prices are sample data."

    get quote_path(quote, line: quote.quote_lines.second.id)
    assert_response :success
  end

  test "export requires approval, then returns a labeled sample CSV" do
    quote = create_demo_quote

    get export_quote_path(quote)
    assert_redirected_to quote_path(quote)

    post approve_quote_path(quote), params: { reviewed: "1", reviewed_version: quote.reload.review_revision }
    assert_redirected_to quote_path(quote)
    assert quote.reload.approved?

    get export_quote_path(quote)
    assert_response :success
    assert_match %r{\Atext/csv}, response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    refute_match(/SAMPLE/, response.headers["Content-Disposition"])
    refute_includes response.body, "SAMPLE DATA"
    assert_includes response.body, %("4640.00")
  end

  test "approval requires explicit review confirmation" do
    quote = create_demo_quote
    [nil, "0", "true"].each do |value|
      post approve_quote_path(quote), params: { reviewed: value }
      assert_redirected_to quote_path(quote)
      refute quote.reload.approved?
    end
  end

  test "a stale browser review cannot approve newer changes" do
    quote = create_demo_quote
    revision = quote.review_revision
    quote.quote_lines.first.apply_manual_edit("notes" => "New review detail")
    post approve_quote_path(quote), params: { reviewed: "1", reviewed_version: revision }
    assert_redirected_to quote_path(quote)
    refute quote.reload.approved?
  end

  test "a line edit invalidates approval and blocks export" do
    quote = create_demo_quote
    post approve_quote_path(quote), params: { reviewed: "1", reviewed_version: quote.reload.review_revision }
    assert quote.reload.approved?
    ready_line = quote.quote_lines.first

    patch quote_quote_line_path(quote, ready_line), params: { reviewed_version: quote.reload.review_revision, quote_line: { notes: "Confirm the delivery window." } }
    assert_redirected_to quote_path(quote, line: ready_line.id)

    refute quote.reload.approved?
    assert_equal "Confirm the delivery window.", ready_line.reload.notes

    get export_quote_path(quote)
    assert_redirected_to quote_path(quote)
  end

  test "a spec edit through nested parameters sends the line back to the buyer" do
    quote = create_demo_quote
    ready_line = quote.quote_lines.first

    patch quote_quote_line_path(quote, ready_line),
      params: { reviewed_version: quote.reload.review_revision, quote_line: { spec: { material: "Carbon steel" }, catalog_sku: "SAMPLE-INVENTED", state: "ready" } }
    assert_response :redirect

    ready_line.reload
    assert_equal "needs_buyer", ready_line.state
    assert_equal "Carbon steel", ready_line.spec_value("material")
    assert_equal "SAMPLE-SS304-16GA-48X96-2B", ready_line.catalog_sku
    assert_equal BigDecimal("0"), quote.reload.subtotal
  end

  test "an invalid line edit is rejected in the page and nothing is saved" do
    quote = create_demo_quote
    ready_line = quote.quote_lines.first

    patch quote_quote_line_path(quote, ready_line), params: { reviewed_version: quote.reload.review_revision, quote_line: { quantity: "abc", unit_price: "-4" } }
    assert_response 422

    ready_line.reload
    assert_equal BigDecimal("20"), ready_line.quantity
    assert_equal BigDecimal("232.00"), ready_line.unit_price
    assert_equal "ready", ready_line.state
  end

  test "approval is refused while a held line has no question" do
    quote = create_demo_quote
    quote.quote_lines.third.update!(clarification_question: nil)

    post approve_quote_path(quote), params: { reviewed: "1", reviewed_version: quote.reload.review_revision }
    assert_redirected_to quote_path(quote)
    refute quote.reload.approved?
  end

  test "another browser session cannot reach this session's quote" do
    quote = create_demo_quote
    ready_line = quote.quote_lines.first
    other_browser = open_session

    other_browser.get quote_path(quote)
    assert_equal 404, other_browser.response.status

    other_browser.post approve_quote_path(quote), params: { reviewed: "1", reviewed_version: quote.reload.review_revision }
    assert_equal 404, other_browser.response.status

    other_browser.get export_quote_path(quote)
    assert_equal 404, other_browser.response.status

    other_browser.get source_quote_path(quote)
    assert_equal 404, other_browser.response.status

    other_browser.patch quote_quote_line_path(quote, ready_line), params: { reviewed_version: quote.reload.review_revision, quote_line: { unit_price: "1.00" } }
    assert_equal 404, other_browser.response.status

    refute quote.reload.approved?
    assert_equal BigDecimal("232.00"), ready_line.reload.unit_price

    get quote_path(quote)
    assert_response :success
  end

  test "each browser session gets its own demo quotes" do
    first_quote = create_demo_quote
    other_browser = open_session
    second_quote = create_demo_quote(other_browser)

    refute_equal first_quote.workspace_token, second_quote.workspace_token

    other_browser.get quote_path(first_quote)
    assert_equal 404, other_browser.response.status
    get quote_path(second_quote)
    assert_response :not_found
  end

  test "pasted RFQ text is saved and awaits processing" do
    assert_difference "Quote.count", 1 do
      post quotes_path, params: { quote: { title: "Pasted RFQ", buyer_name: "Northline Fabrication", source_text: "Please quote 10 sheets of 304." } }
    end
    quote = Quote.find(quote_id_from_redirect)

    assert quote.awaiting_processing?
    refute quote.sample_data?
    follow_redirect!
    assert_response :success
  end

  test "an empty intake is rejected in the page" do
    assert_no_difference "Quote.count" do
      post quotes_path, params: { quote: { title: "", buyer_name: "", source_text: "" } }
    end
    assert_response 422
  end

  test "an uploaded file is stored as bytes and downloaded as an attachment" do
    bytes = "%PDF-1.4 sample bytes \x00\xFF".b

    post quotes_path, params: { quote: { title: "PDF RFQ", buyer_name: "", source_text: "", source_file: upload(bytes, "rfq 2210.pdf") } }
    quote = Quote.find(quote_id_from_redirect)

    assert_equal "rfq 2210.pdf", quote.original_filename
    assert_equal bytes, quote.source_bytes.b
    assert quote.awaiting_processing?

    get source_quote_path(quote)
    assert_response :success
    assert_equal "application/octet-stream", response.media_type
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
    assert_equal bytes, response.body.b
  end

  test "an HTML upload is refused" do
    assert_no_difference "Quote.count" do
      post quotes_path, params: { quote: { title: "Bad type", source_text: "", source_file: upload("<script>alert(1)</script>", "rfq.html", "text/html") } }
    end
    assert_response 422
  end

  test "an upload over 10 MB is refused" do
    oversized = "a" * (Quote::MAXIMUM_SOURCE_BYTES + 1)

    assert_no_difference "Quote.count" do
      post quotes_path, params: { quote: { title: "Oversized", source_text: "", source_file: upload(oversized, "large.pdf") } }
    end
    assert_response 422
  end

  test "pasted text over 50,000 characters is refused" do
    assert_no_difference "Quote.count" do
      post quotes_path, params: { quote: { title: "Long", source_text: "a" * 50_001 } }
    end
    assert_response 422
  end

  test "pasted text downloads as a text attachment" do
    quote = create_demo_quote

    get source_quote_path(quote)
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
    assert_includes response.body, "Northline Fabrication"
  end
  test "approval form accepts ready lines beside internal holds without demanding questions" do
    quote = create_demo_quote
    quote.quote_lines.second.update!(clarification_question: nil, catalog_sku: "KNOWN", unit_price: nil,
      unresolved_fields: ["unit_price"], processing: {"match" => {"status" => "exact"}})
    quote.quote_lines.third.update!(clarification_question: nil,
      processing: {"match" => {"status" => "no_match", "reason" => "Unsupported screw"}})
    get quote_path(quote)
    assert_response :success
    assert_select ".approval input[type=submit][value='Approve quote']", count: 1
    assert_select ".approval", text: /The rep must confirm pricing/
    assert_select ".approval", text: /No catalog item fits this request/
    refute_includes response.body, "No question yet. Add one on this line before approval."
    post approve_quote_path(quote), params: {reviewed: "1", reviewed_version: quote.reload.review_revision}
    assert_redirected_to quote_path(quote)
    assert quote.reload.approved?
  end

end
