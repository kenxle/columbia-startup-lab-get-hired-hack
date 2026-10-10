require "test_helper"

# RFQ_Demo flow: every line Ready -> "attention needed: approve" -> approving
# emails the buyer automatically -> the page links to the proposal itself.
class AutoSendOnApprovalTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { ActionMailer::Base.deliveries.clear }
  teardown { ActionMailer::Base.deliveries.clear }

  def ready_quote
    post quotes_path, params: { quote: { title: "RFQ_Demo", buyer_name: "Gulf Coast Castings",
                                         source_text: File.read(Rails.root.join("docs/product/demo_rfq/RFQ_Demo.txt")) } }
    quote = Quote.order(:id).last
    perform_enqueued_jobs only: ProcessRfqJob
    quote.reload
  end

  test "an all-Ready quote asks for approval, sends itself on approval and links to the proposal" do
    quote = ready_quote
    assert_equal 4, quote.quote_lines.count
    assert quote.quote_lines.all?(&:quotable?), quote.quote_lines.map(&:state).inspect

    get quote_path(quote)
    assert_select ".ready-banner", text: /Attention needed: approve/

    post approve_quote_path(quote), params: { reviewed: "1", reviewed_version: quote.reload.review_revision }
    assert_redirected_to quote_path(quote)
    assert quote.reload.approved?
    assert quote.sent?, "approval of an all-Ready quote sends it"
    assert_equal 1, ActionMailer::Base.deliveries.size

    follow_redirect!
    assert_match(/emailed to the buyer automatically/, flash[:notice].to_s + response.body)
    assert_select ".proposal-links a[href=?]", quote_final_quote_path(quote), text: "Open the proposal"
    assert_select ".proposal-links a[href=?]", pdf_quote_final_quote_path(quote)
    assert_select ".ready-banner", count: 0
  end

  test "a quote with held lines is approved without an automatic email" do
    post quotes_path, params: { quote: { title: "Mixed", buyer_name: "Northline",
                                         source_text: "Steel shot S-330, 2,000 lb\nStainless 304, 0.060 in, 48 x 96, 10 sheets" } }
    quote = Quote.order(:id).last
    perform_enqueued_jobs only: ProcessRfqJob
    get quote_path(quote)
    assert_select ".ready-banner", count: 0
    post approve_quote_path(quote), params: { reviewed: "1", reviewed_version: quote.reload.review_revision }
    assert_not quote.reload.sent?
    assert_empty ActionMailer::Base.deliveries
  end
end
