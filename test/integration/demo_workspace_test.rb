require "test_helper"
require "minitest/mock"

class DemoWorkspaceFlowTest < ActionDispatch::IntegrationTest
  test "first development visit shows three material RFQs and refresh does not duplicate them" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      assert_difference "Quote.count", 3 do
        get quotes_path
      end
      assert_response :success
      assert_includes response.body, "Sheet and plate sourcing"
      assert_includes response.body, "Steel shot replenishment"
      assert_includes response.body, "Structural plate order"
      assert_no_difference("Quote.count") { get quotes_path }
      browser = open_session
      assert_difference "Quote.count", 3 do
        browser.get quotes_path
      end
      assert_equal 200, browser.response.status
    end
  end

  test "test and production listing stay empty without inserting samples" do
    assert_no_difference("Quote.count") { get quotes_path }
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_no_difference("Quote.count") { get quotes_path }
    end
    assert_response :success
  end

  test "existing development workspace is preserved and explicit demo action stays compatible" do
    post demo_quotes_path
    quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    assert_redirected_to quote_path(quote)
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      assert_no_difference("Quote.count") { get quotes_path }
      assert_difference "Quote.count", 1 do
        post demo_quotes_path
      end
    end
    assert_equal 3, quote.quote_lines.count
    assert_equal BigDecimal("4640"), quote.subtotal
  end
end
