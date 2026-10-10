require "test_helper"

class QuoteDeadlinesUiTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
  end

  test "list and quote page show the same deadline and move through warning and overdue states" do
    travel_to Time.utc(2026, 10, 10, 14, 0, 0) do
      @quote.update_columns(created_at: 20.hours.ago - 40.minutes)
      get quotes_path
      assert_response :success
      assert_select ".page-lede", "Review incoming RFQs, resolve questions, and prepare quotes for approval."
      assert_select 'th[scope="col"]', "Due"
      assert_select ".deadline--calm", "Due in 3h 20m"
      assert_select 'script[src*="quote_deadlines"][defer]'

      get quote_path(@quote)
      assert_select '.page-deadline .deadline--calm[data-quote-deadline="due"][data-deadline-at=?]', @quote.due_at.iso8601, text: "Due in 3h 20m"
      assert_select ".brand-header", count: 0
    end

    travel_to Time.utc(2026, 10, 10, 14, 20, 0) do
      get quote_path(@quote)
      assert_select ".page-deadline .deadline--soon", "Due in 3h 00m"
    end

    travel_to Time.utc(2026, 10, 10, 18, 25, 0) do
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
    assert_select ".page-actions .status--needs-buyer", "Needs the buyer"

    @quote.quote_lines.where(state: "needs_buyer").delete_all
    get quote_path(@quote)
    assert_select ".page-actions .status--no-match", "No match"

    @quote.approve!
    get quote_path(@quote)
    assert_select ".page-actions .status--ready", "Ready to send"
    assert_select '.page-deadline [data-quote-deadline="due"]'
    assert_select '.page-deadline [data-quote-deadline="sent"]', count: 0
  end
end
