require "test_helper"
require "minitest/mock"

class DemoWorkspaceFlowTest < ActionDispatch::IntegrationTest
  test "new desk covers calm warning overdue and sent examples sorted by due time" do
    travel_to Time.utc(2026, 10, 10, 14, 0, 0) do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) { get quotes_path }
      quotes = Quote.all.to_a
      ages = quotes.map { |quote| (Time.current - quote.created_at) / 1.hour }
      [0.5, 4, 9, 14, 19, 22, 23.5].each { |age| assert_includes ages, age }
      assert quotes.any? { |quote| !quote.sent? && quote.due_at < Time.current }
      assert_equal 2, quotes.count(&:sent?)
      assert_select ".deadline--calm", minimum: 1
      assert_select ".deadline--soon", minimum: 1
      assert_select ".deadline--overdue", minimum: 1
      assert_select ".deadline--sent", count: 2
      expected = quotes.sort_by { |quote| [quote.sent? ? 1 : 0, quote.due_at, quote.id] }.map(&:reference)
      assert_select "tbody tr th .row-link" do |links|
        assert_equal expected, links.map { |link| link.text.strip }
      end
      before = quotes.to_h { |quote| [quote.id, quote.created_at] }
      travel 1.hour
      Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) { get quotes_path }
      assert_equal before, Quote.all.to_h { |quote| [quote.id, quote.created_at] }
    end
  end

  test "first development visit shows twelve material RFQs and refresh does not duplicate them" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      assert_difference "Quote.count", 12 do
        get quotes_path
      end
      assert_response :success
      assert_includes response.body, "Sheet and plate sourcing"
      assert_includes response.body, "Steel shot replenishment"
      assert_includes response.body, "Structural plate order"
      assert_no_difference("Quote.count") { get quotes_path }
      browser = open_session
      assert_difference "Quote.count", 12 do
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
