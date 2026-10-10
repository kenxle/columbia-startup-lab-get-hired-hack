require "test_helper"

class BuyerTermsTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    @line = @quote.quote_lines.first
  end

  def payload
    { quote_line_id: @line.id, reviewed_version: @quote.review_revision, term: "KB", field: "finish", value: "#4" }
  end

  test "explicit scoped POST teaches one term with server supplied provenance" do
    assert_difference "ClientTerm.count", 1 do
      post quote_buyer_terms_path(@quote), params: payload.merge(source: "learned", client_id: 999,
        provenance: { quote_reference: "FORGED", quote_id: 999 })
    end
    assert_redirected_to quote_path(@quote, line: @line.id, anchor: "line-detail")
    record = ClientTerm.last
    assert_equal "taught", record.source
    assert_equal @quote.reference, record.meaning["provenance"]["quote_reference"]
    assert_equal @quote.id, record.meaning["provenance"]["quote_id"]
    follow_redirect!
    assert_select ".flash--notice", text: /taught on #{@quote.reference}/
  end

  test "cross session quote and unrelated line ids return not found" do
    other = open_session
    assert_no_difference "ClientTerm.count" do
      other.post quote_buyer_terms_path(@quote), params: payload
    end
    assert_equal 404, other.response.status
    unrelated = QuoteWorkspace::Demo.create!(workspace_token: @quote.workspace_token)
    post quote_buyer_terms_path(@quote), params: payload.merge(quote_line_id: unrelated.quote_lines.first.id)
    assert_response :not_found
    assert_equal 0, ClientTerm.count
  end

  test "stale revision and unsupported field show recoverable errors without teaching" do
    [ payload.merge(reviewed_version: "old"), payload.merge(field: "unit_price") ].each do |parameters|
      assert_no_difference "ClientTerm.count" do
        post quote_buyer_terms_path(@quote), params: parameters
      end
      assert_redirected_to quote_path(@quote, line: @line.id, anchor: "line-detail")
      follow_redirect!
      assert_select ".flash--alert", count: 1
    end
  end
end
