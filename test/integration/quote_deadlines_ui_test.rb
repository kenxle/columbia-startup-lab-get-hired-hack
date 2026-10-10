require "test_helper"

class QuoteDeadlinesUiTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
  end

  test "list and quote page show the same deadline and move through warning and overdue states" do
    travel_to Time.utc(2026, 10, 10, 14, 0, 0) do
      @quote.update_columns(created_at: 16.hours.ago)
      get quotes_path
      assert_response :success
      assert_select ".page-lede", "Review incoming RFQs, resolve questions, and prepare quotes for approval."
      assert_select 'th[scope="col"]', "Due"
      assert_select ".deadline--calm", "Due in 8h 00m"
      assert_select 'script[src*="quote_deadlines"][defer]'

      get quote_path(@quote)
      assert_select '.page-deadline .deadline--calm[data-quote-deadline="due"][data-deadline-at=?]', @quote.due_at.iso8601, text: "Due in 8h 00m"
      assert_select ".brand-header", count: 0
    end

    travel_to Time.utc(2026, 10, 10, 14, 0, 1) do
      get quote_path(@quote)
      assert_select ".page-deadline .deadline--soon", "Due in 8h 00m"
    end

    travel_to Time.utc(2026, 10, 10, 22, 0, 0) do
      get quote_path(@quote)
      assert_select ".page-deadline .deadline--overdue", "Overdue by 0h 00m"
    end

    travel_to Time.utc(2026, 10, 10, 23, 5, 0) do
      get quote_path(@quote)
      assert_select ".page-deadline .deadline--overdue", "Overdue by 1h 05m"
    end
  end

  test "current sent revision displays fixed turnaround and sent status" do
    travel_to Time.utc(2026, 10, 10, 14, 0, 0) do
      received_at = 10.hours.ago
      @quote.approve!
      @quote.update_columns(created_at: received_at, sent_at: received_at + 65.minutes,
        sent_review_revision: @quote.review_revision)
      get quote_path(@quote)
      assert_response :success
      assert_select '.page-deadline .deadline--sent[data-quote-deadline="sent"]', "Sent in 1h 05m"
      assert_select ".page-actions .status--ready", "Sent"
      assert_select "title", "Sent · #{@quote.reference} · Quote Desk"

      @quote.touch(time: 1.second.from_now)
      get quote_path(@quote)
      assert_select ".page-deadline .deadline--sent", count: 0
      assert_select '.page-deadline [data-quote-deadline="due"]'
    end
  end

  test "review status shows buyer attention until approval and never claims a preview was sent" do
    get quote_path(@quote)
    assert_select ".page-actions .status--needs-buyer", "Question to send"

    @quote.quote_lines.where(state: "needs_buyer").delete_all
    @quote.quote_lines.find_by!(state: "no_match").update!(clarification_question: nil,
      processing: {"match" => {"status" => "no_match", "reason" => "No catalog item fits."}})
    get quote_path(@quote)
    assert_select ".page-actions .status--no-match", "No match"

    @quote.approve!
    get quote_path(@quote)
    assert_select ".page-actions .status--ready", "Ready to send"
    assert_select '.page-deadline [data-quote-deadline="due"]'
    assert_select '.page-deadline [data-quote-deadline="sent"]', count: 0
  end

  test "unsent question labels persist across the list filters and local question preview" do
    held_line = @quote.quote_lines.find_by!(state: "needs_buyer")
    get quotes_path
    assert_select ".status--needs-buyer", "Question to send"
    refute_includes response.body, "Needs the buyer"
    refute_includes response.body, "Waiting on buyer"

    %w[all attention].each do |filter|
      get quote_path(@quote, status: filter, line: held_line.id)
      assert_response :success
      assert_select ".status--needs-buyer", text: "Question to send", minimum: 1
      assert_select "title", "2 questions to send · #{@quote.reference} · Quote Desk"
      assert_select ".callout--held strong", "Question to send."
      refute_includes response.body, "Needs the buyer"
      refute_includes response.body, "Waiting on buyer"
    end

    post preview_email_quote_buyer_questions_path(@quote), params: { reviewed_version: @quote.review_revision }
    assert_redirected_to quote_buyer_questions_path(@quote)
    follow_redirect!
    assert_select ".buyer-draft__badge", "Draft, not sent"
    assert_includes response.body, "Nothing was sent to the buyer."
    assert_select "title", "2 questions to send · #{@quote.reference} · Quote Desk"
    assert_equal "needs_buyer", held_line.reload.state
    assert_equal "Question to send", held_line.status_label
    assert_nil @quote.reload.sent_at

    get quote_path(@quote)
    assert_select ".page-actions .status--needs-buyer", "Question to send"
    refute_includes response.body, "Waiting on buyer"
  end

  test "final quote delivery does not claim its unanswered question was delivered" do
    @quote.approve!
    @quote.update_columns(sent_at: Time.current, sent_review_revision: @quote.review_revision)

    get quote_path(@quote, status: "all")
    assert_select ".page-actions .status--ready", "Sent"
    assert_select ".status--needs-buyer", text: "Question to send", minimum: 1
    refute_includes response.body, "Waiting on buyer"
  end
end
