require "test_helper"
require "pdf/reader"
require "stringio"

class FinalQuotesTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    ActionMailer::Base.deliveries.clear
  end

  test "approval unlocks the email preview and real PDF download" do
    get quote_final_quote_path(@quote)
    assert_redirected_to quote_path(@quote)
    get pdf_quote_final_quote_path(@quote)
    assert_redirected_to quote_path(@quote)
    get download_quote_final_quote_path(@quote)
    assert_redirected_to quote_path(@quote)
    @quote.approve!
    get quote_path(@quote)
    assert_select "a[href=?]", quote_final_quote_path(@quote), text: "Prepare email and PDF"
    get quote_final_quote_path(@quote)
    assert_response :success
    assert_select "h1", "Email and quote documents"
    assert_select ".buyer-draft__badge", "Draft, not sent"
    assert_select "a[href=?]", pdf_quote_final_quote_path(@quote)
    assert_select "form[action=?]", preview_email_quote_final_quote_path(@quote)
    assert_includes response.headers["Cache-Control"], "no-store"
    get pdf_quote_final_quote_path(@quote)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_match(/attachment.*SAMPLE.pdf/, response.headers["Content-Disposition"])
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    assert_includes text, "4640.00"
    assert_includes text, "Lead time: to confirm"
    assert_includes text, "SAMPLE DATA"
  end

  test "email draft escapes HTML and excludes private data" do
    @quote.quote_lines.first.apply_manual_edit("notes" => "SECRET-NOTE", "description" => "<script>alert('bad')</script>")
    @quote.approve!
    get quote_final_quote_path(@quote)
    assert_response :success
    assert_select "script", count: 0
    assert_includes response.body, "&lt;script&gt;"
    refute_includes response.body, "SECRET-NOTE"
    get download_quote_final_quote_path(@quote)
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "Draft, not sent"
    refute_includes response.body, "SECRET-NOTE"
  end

  test "another browser cannot access final quote artifacts or mail preview" do
    @quote.approve!
    other = open_session
    [quote_final_quote_path(@quote), pdf_quote_final_quote_path(@quote), download_quote_final_quote_path(@quote)].each do |path|
      other.get path
      assert_equal 404, other.response.status
    end
    other.post preview_email_quote_final_quote_path(@quote), params: { reviewed_version: @quote.review_revision }
    assert_equal 404, other.response.status
    other.post preview_email_quote_buyer_questions_path(@quote), params: { reviewed_version: @quote.review_revision }
    assert_equal 404, other.response.status
    assert_empty ActionMailer::Base.deliveries
  end

  test "local quote preview includes both documents and does not mutate approval" do
    @quote.approve!
    before = @quote.reload.attributes
    post preview_email_quote_final_quote_path(@quote), params: { reviewed_version: @quote.review_revision }
    assert_redirected_to quote_final_quote_path(@quote)
    assert_equal 1, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.last
    assert_equal 2, mail.attachments.size
    assert_equal ["buyer@example.invalid"], mail.to
    assert_equal before, @quote.reload.attributes
  end

  test "edits revoke output and stale preview clicks create no mail" do
    @quote.approve!
    version = @quote.review_revision
    @quote.quote_lines.first.apply_manual_edit("notes" => "Updated after review")
    get pdf_quote_final_quote_path(@quote)
    assert_redirected_to quote_path(@quote)
    post preview_email_quote_final_quote_path(@quote), params: { reviewed_version: version }
    assert_redirected_to quote_path(@quote)
    post preview_email_quote_final_quote_path(@quote), params: { reviewed_version: @quote.reload.review_revision }
    assert_redirected_to quote_path(@quote)
    assert_empty ActionMailer::Base.deliveries
  end

  test "questions can preview without quote approval but require current complete questions" do
    post preview_email_quote_buyer_questions_path(@quote), params: { reviewed_version: @quote.review_revision }
    assert_redirected_to quote_buyer_questions_path(@quote)
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_empty ActionMailer::Base.deliveries.last.attachments
    @quote.quote_lines.second.apply_manual_edit("clarification_question" => "")
    post preview_email_quote_buyer_questions_path(@quote), params: { reviewed_version: @quote.reload.review_revision }
    assert_redirected_to quote_buyer_questions_path(@quote)
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "unsupported PDF characters give an exact text alternative and no email" do
    @quote.quote_lines.first.apply_manual_edit("description" => "Unsupported character \u{10FFFF}")
    @quote.approve!
    get pdf_quote_final_quote_path(@quote)
    assert_redirected_to quote_final_quote_path(@quote)
    follow_redirect!
    assert_includes response.body, "Download the text or CSV"
    post preview_email_quote_final_quote_path(@quote), params: { reviewed_version: @quote.review_revision }
    assert_redirected_to quote_final_quote_path(@quote)
    assert_empty ActionMailer::Base.deliveries
  end
end
