require "test_helper"
require "minitest/mock"

class PricingRunsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    post quotes_path, params: { quote: { title: "TEST pricing RFQ", source_text: "AN3-13A qty 1 ea" } }
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    clear_enqueued_jobs
    ProcessingRun.where(quote: @quote).delete_all
  end

  def submit(**options)
    post quote_pricing_path(@quote), params: { reviewed_version: @quote.reload.review_revision,
      pricing: { country: "US", postal_code: "10027", currency: "USD" }.merge(options) }
  end

  def result
    { "schema" => "distributor_pricing/v1", "calculated_at" => Time.current.iso8601,
      "quote" => { "currency" => "USD", "total" => nil, "held_lines" => 1, "ready_lines" => 0 },
      "lines" => [{ "original_text" => "<script>alert('TEST')</script>", "quantity" => "1", "unit" => "each",
        "pricing" => { "status" => "needs_procurement", "unit_price" => nil, "procurement_tasks" => ["TEST freight unknown"] },
        "competitor_coverage" => { "required" => 5, "gap" => 5 },
        "public_market_prices" => [{ "supplier" => "TEST Dealer", "currency" => "USD", "unit_price" => "1.00",
          "unit" => "each", "retrieved_at" => Time.current.iso8601, "source_url" => "javascript:alert('TEST')" }] }] }
  end

  test "get shows required destination and never fetches pricing sources" do
    called = false
    DistributorPricing::QuoteAgent.stub(:call, ->(**_) { called = true }) do
      get quote_pricing_path(@quote)
      assert_response :success
      assert_select 'input[name="pricing[country]"][required]', count: 1
      assert_select 'input[name="pricing[postal_code]"][required]', count: 1
      assert_select 'input[name="reviewed_version"][value=?]', @quote.review_revision
      assert_select 'input[type="submit"][value="Check current prices"]', count: 1
    end
    refute called
    assert_no_difference("PricingRun.count") { get quote_pricing_path(@quote) }
  end

  test "POST enqueues once and JSON exposes scoped status" do
    assert_enqueued_jobs 1, only: PriceRfqJob do
      submit
      assert_redirected_to quote_pricing_path(@quote)
      submit
    end
    assert_equal 1, PricingRun.where(quote: @quote).count
    get quote_pricing_path(@quote, format: :json)
    assert_response :success
    assert_equal "queued", response.parsed_body["status"]
    assert_nil response.parsed_body["result"]
  end

  test "pricing routes are scoped to their browser session" do
    other = open_session
    other.get quote_pricing_path(@quote)
    assert_equal 404, other.response.status
    assert_no_enqueued_jobs do
      other.post quote_pricing_path(@quote), params: { reviewed_version: @quote.review_revision,
        pricing: { country: "US", postal_code: "10027", currency: "USD" } }
    end
    assert_equal 404, other.response.status
  end

  test "empty destination rejects pricing and preserves quote" do
    assert_no_enqueued_jobs { submit(postal_code: "") }
    assert_equal 0, PricingRun.where(quote: @quote).count
    assert_redirected_to quote_pricing_path(@quote)
  end

  test "completed held prices show evidence without executable total or script links" do
    DistributorPricing::QuoteAgent.stub(:call, result) do
      perform_enqueued_jobs(only: PriceRfqJob) { submit }
    end
    get quote_pricing_path(@quote)
    assert_response :success
    assert_includes response.body, "Quote pricing is held or expired."
    assert_includes response.body, "TEST freight unknown"
    assert_includes response.body, "Current public product prices"
    assert_includes response.body, "&lt;script&gt;"
    refute_includes response.body, "<script>alert('TEST')</script>"
    assert_select 'a[href^="javascript:"]', count: 0
    get quote_pricing_path(@quote, format: :json)
    assert_nil response.parsed_body.dig("result", "quote", "total")
    assert_equal false, response.parsed_body["quote_prices_current"]
  end

  test "changed quote hides previous pricing evidence in html and json" do
    DistributorPricing::QuoteAgent.stub(:call, result) { perform_enqueued_jobs(only: PriceRfqJob) { submit } }
    @quote.update!(source_text: "AN3-14A qty 2 ea")
    get quote_pricing_path(@quote)
    assert_includes response.body, "The RFQ changed."
    refute_includes response.body, "TEST freight unknown"
    get quote_pricing_path(@quote, format: :json)
    assert_nil response.parsed_body["result"]
    assert_equal false, response.parsed_body["current"]
  end
end
