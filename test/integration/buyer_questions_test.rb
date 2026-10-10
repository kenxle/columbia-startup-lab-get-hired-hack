require "test_helper"

class BuyerQuestionsTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
  end

  test "sample preview consolidates held questions and links to existing editors" do
    get quote_buyer_questions_path(@quote)
    assert_response :success
    assert_select "h1", "Review buyer questions"
    assert_select ".buyer-draft__badge", "Draft, not sent"
    assert_select ".buyer-draft__sample", count: 0
    assert_select ".buyer-draft__questions > li", count: 2
    @quote.quote_lines.reject(&:quotable?).each do |line|
      assert_select "a[href=?]", quote_path(@quote, line: line.id, return_to: "buyer_questions", anchor: "line-detail"), text: "Edit question"
      assert_select ".buyer-draft__question", text: line.clarification_question
    end
    assert_select "a[href=?]", download_quote_buyer_questions_path(@quote), text: "Download draft (.txt)"
    assert_includes response.body, "Open a local email preview or download the draft."
  end

  test "download is a plain text draft without prices internal notes or source content" do
    @quote.quote_lines.second.update!(notes: "PRIVATE-INTERNAL-NOTE", original_text: "PRIVATE-SOURCE-LINE", unit_price: 987.6543)
    @quote.update!(source_text: "PRIVATE-FULL-RFQ", source_bytes: "PRIVATE-BYTES", original_filename: "PRIVATE.txt")
    get download_quote_buyer_questions_path(@quote)
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match(/attachment.*#{@quote.reference}-buyer-questions.txt/, response.headers["Content-Disposition"])
    assert_includes response.body, "Draft, not sent"
    refute_includes response.body, "SAMPLE DATA"
    @quote.quote_lines.reject(&:quotable?).each { |line| assert_includes response.body, line.clarification_question }
    %w[PRIVATE-INTERNAL-NOTE PRIVATE-SOURCE-LINE 987.6543 232 4640 PRIVATE-FULL-RFQ PRIVATE-BYTES].each do |private_value|
      refute_includes response.body, private_value
    end
  end

  test "missing question shows actionable link and blocks direct download" do
    line = @quote.quote_lines.second
    line.update!(clarification_question: " \n")
    get quote_buyer_questions_path(@quote)
    assert_response :success
    assert_select "[role=alert]", /Add the missing questions/
    assert_select "a[href=?]", quote_path(@quote, line: line.id, return_to: "buyer_questions", anchor: "line-detail"), text: "Add a question for line 2"
    assert_select "a[href=?]", download_quote_buyer_questions_path(@quote), count: 0
    get download_quote_buyer_questions_path(@quote)
    assert_redirected_to quote_buyer_questions_path(@quote)
    assert_nil response.headers["Content-Disposition"]
  end

  test "quote with no held lines offers no download" do
    @quote.quote_lines.where.not(state: "ready").delete_all
    get quote_buyer_questions_path(@quote)
    assert_response :success
    assert_select "h2", "No buyer questions to draft"
    assert_includes response.body, "There are no held lines in this quote."
    assert_select "a[href=?]", download_quote_buyer_questions_path(@quote), count: 0
    get download_quote_buyer_questions_path(@quote)
    assert_redirected_to quote_buyer_questions_path(@quote)
  end

  test "empty quote explains that processing is pending" do
    @quote.quote_lines.delete_all
    get quote_buyer_questions_path(@quote)
    assert_response :success
    assert_includes response.body, "This RFQ is awaiting processing."
    assert_select "a[href=?]", download_quote_buyer_questions_path(@quote), count: 0
    get download_quote_buyer_questions_path(@quote)
    assert_redirected_to quote_buyer_questions_path(@quote)
  end

  test "another browser cannot preview or download questions" do
    other_browser = open_session
    other_browser.get quote_buyer_questions_path(@quote)
    assert_equal 404, other_browser.response.status
    other_browser.get download_quote_buyer_questions_path(@quote)
    assert_equal 404, other_browser.response.status
  end

  test "preview and download neither approve nor mutate quotes and preserve existing approval" do
    [ false, true ].each do |approved|
      @quote.approve! if approved
      before_attributes = @quote.reload.attributes
      before_lines = @quote.quote_lines.map(&:attributes)
      get quote_buyer_questions_path(@quote)
      assert_response :success
      get download_quote_buyer_questions_path(@quote)
      assert_response :success
      assert_equal before_attributes, @quote.reload.attributes
      assert_equal before_lines, @quote.quote_lines.reload.map(&:attributes)
      assert_equal approved, @quote.approved?
    end
  end

  test "buyer and question strings are escaped in HTML and remain plain text in download" do
    malicious = '<script>alert("buyer")</script><img src=x onerror=alert(1)>'
    @quote.update!(buyer_name: malicious)
    @quote.quote_lines.second.update!(clarification_question: malicious)
    get quote_buyer_questions_path(@quote)
    assert_response :success
    assert_select ".buyer-draft script, .buyer-draft img", count: 0
    assert_select ".buyer-draft__question", text: malicious
    assert_includes response.body, "&lt;script&gt;"
    get download_quote_buyer_questions_path(@quote)
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, malicious
  end

  test "question edits preserve preview return through validation failure and successful save" do
    line = @quote.quote_lines.second
    get quote_path(@quote, line: line.id, return_to: "buyer_questions", anchor: "line-detail")
    assert_response :success
    assert_select '.line-form input[name="return_to"][value="buyer_questions"]'

    patch quote_quote_line_path(@quote, line), params: {
      status: "all", return_to: "buyer_questions", quote_line: { clarification_question: "?" * 1001 }
    }
    assert_response 422
    assert_select "#line-detail .form-errors", count: 1
    assert_select '.line-form input[name="return_to"][value="buyer_questions"]'
    assert_select '.line-form input[name="status"][value="all"]'

    patch quote_quote_line_path(@quote, line), params: {
      status: "all", return_to: "buyer_questions", quote_line: { clarification_question: "Which grade do you need?" }
    }
    assert_redirected_to quote_buyer_questions_path(@quote)
    follow_redirect!
    assert_select ".buyer-draft__question", text: "Which grade do you need?"
  end
end
