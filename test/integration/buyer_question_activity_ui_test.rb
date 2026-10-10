require "test_helper"

class BuyerQuestionActivityUiTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    @line = @quote.quote_lines.find_by!(state: "needs_buyer")
  end

  def record_preview(line = @line, status: "previewed")
    line.buyer_question_deliveries.create!(
      quote: @quote, fingerprint: line.question_delivery_fingerprint,
      channel: "local_preview", status: status, recipient: "buyer@example.invalid",
      buyer_name: @quote.buyer_name, line_position: line.position, source_line_id: line.line_id,
      question_text: line.clarification_question,
      previewed_at: status == "previewed" ? Time.current : nil)
  end

  test "successful local question preview shows waiting with its time recipient and exact text" do
    delivery = record_preview

    get quote_path(@quote, line: @line.id)
    assert_response :success
    assert_select ".page-actions .status--needs-buyer", "Waiting on buyer"
    assert_select ".question-preview-status .lines-table__sku", "Local demo preview"
    assert_select "title", "1 line waiting on buyer (local preview) · #{@quote.reference} · Quote Desk"
    assert_select ".summary__item", text: /Waiting on buyer.*local preview.*1/m
    assert_select ".question-preview-detail" do
      assert_select 'time[datetime=?]', delivery.previewed_at.iso8601
      assert_select "dd", "buyer@example.invalid"
      assert_select ".quote-text", delivery.question_text
      assert_select ".field__hint", /No email was sent to the buyer/
    end
    assert_select ".question-activity__event", count: 1
    assert_select ".question-activity", /Local demo mail previews only/
    assert_select ".callout--held strong", "Waiting on buyer."
    assert_select ".callout--held", /the rest of the quote can continue/
    assert_nil @quote.reload.sent_at

    get quotes_path
    assert_select ".question-preview-status .status--needs-buyer", "Waiting on buyer"
    assert_select ".question-preview-status .lines-table__sku", "Local demo preview"

    get quote_buyer_questions_path(@quote)
    assert_select ".status--needs-buyer", "Waiting on buyer"
    assert_select ".buyer-draft__badge", "Draft, not sent"
    assert_select ".question-activity__event", count: 1
    assert_select ".field__hint", text: /Local demo preview at.*No email was sent to the buyer/m
  end

  test "an unsent question takes priority while counts retain waiting lines" do
    record_preview
    second = @quote.quote_lines.find_by!(state: "ready")
    second.update!(state: "needs_buyer", clarification_question: "Which finish do you need?")

    get quote_path(@quote, status: "all")
    assert_select ".page-actions .status--needs-buyer", "Question to send"
    assert_select "title", "1 question to send · #{@quote.reference} · Quote Desk"
    assert_select ".summary__item", text: /Question to send.*1/m
    assert_select ".summary__item", text: /Waiting on buyer.*local preview.*1/m
    assert_select ".lines-table .status--needs-buyer", "Waiting on buyer"
    assert_select ".lines-table .status--needs-buyer", "Question to send"
  end

  test "failed preview is not waiting and is excluded from successful activity" do
    record_preview(status: "failed")

    get quote_path(@quote, line: @line.id)
    assert_select ".page-actions .status--needs-buyer", "Question to send"
    assert_select ".question-preview-detail, .question-activity", count: 0
    refute_includes response.body, "Waiting on buyer"
  end

  test "changed question invalidates waiting but keeps the exact earlier activity" do
    delivery = record_preview
    @line.update!(clarification_question: "Please confirm the revised material.")

    get quote_path(@quote, line: @line.id)
    assert_select ".page-actions .status--needs-buyer", "Question to send"
    assert_select ".question-preview-detail", count: 0
    assert_select ".question-activity__event .quote-text", delivery.question_text
    refute_includes response.body, "Waiting on buyer"
  end

  test "stored activity snapshots are escaped in both quote and question views" do
    text = '<img src=x onerror="alert(1)"> Which grade?'
    @line.update!(clarification_question: text)
    delivery = record_preview
    # Legacy stored snapshots remain untrusted even when normal writes validate recipients.
    recipient = '<script>alert("recipient")</script>@example.invalid'
    delivery.update_columns(recipient: recipient)

    [quote_path(@quote, line: @line.id), quote_buyer_questions_path(@quote)].each do |path|
      get path
      assert_response :success
      assert_select ".question-activity script, .question-activity img, .question-preview-detail script, .question-preview-detail img", count: 0
      assert_select ".question-activity__event .quote-text", text
      assert_select ".question-activity__event p", /#{Regexp.escape(recipient)}/
    end
  end

  test "approved quote keeps its ready to send status while the line waits in local demo mode" do
    record_preview
    @quote.approve!

    get quote_path(@quote, status: "all")
    assert_select ".page-actions .status--ready", "Ready to send"
    assert_select ".lines-table .status--needs-buyer", "Waiting on buyer"
    assert_select ".question-activity", /No email was sent to the buyer/
  end
end
