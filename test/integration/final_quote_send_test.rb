require "test_helper"

class FinalQuoteSendTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    @quote.approve!
    ActionMailer::Base.deliveries.clear
  end

  teardown { ActionMailer::Base.deliveries.clear }

  test "send action is explicit scoped idempotent and visible as local on all quote surfaces" do
    get quote_final_quote_path(@quote)
    assert_response :success
    assert_empty ActionMailer::Base.deliveries
    assert_select 'form[action=?]', deliver_quote_final_quote_path(@quote)
    revision = @quote.reload.review_revision
    2.times { post deliver_quote_final_quote_path(@quote), params: { reviewed_version: revision } }
    assert_redirected_to quote_final_quote_path(@quote)
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert @quote.reload.sent_locally?
    follow_redirect!
    assert_select '.buyer-draft__badge', text: 'Sent (local preview)'
    assert_includes response.body, 'buyer@example.invalid (placeholder)'
    assert_includes response.body, 'No real email was sent.'
    assert_select 'form[action=?]', deliver_quote_final_quote_path(@quote), count: 0
    get quote_path(@quote)
    assert_includes response.body, 'Sent (local preview)'
    assert_includes response.body, 'Sent to the local preview inbox'
    get quotes_path
    assert_includes response.body, 'Sent (local preview)'
  end

  test "another workspace and stale forms cannot send" do
    other = open_session
    other.post deliver_quote_final_quote_path(@quote), params: { reviewed_version: @quote.review_revision }
    assert_equal 404, other.response.status
    post deliver_quote_final_quote_path(@quote), params: { reviewed_version: 'old' }
    assert_redirected_to quote_path(@quote)
    assert_empty ActionMailer::Base.deliveries
    refute @quote.reload.sent?
  end
end
