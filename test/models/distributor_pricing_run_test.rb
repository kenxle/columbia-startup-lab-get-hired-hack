require "test_helper"
require "minitest/mock"

class DistributorPricingRunTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @quote = Quote.create!(workspace_token: "TEST-workspace", title: "TEST pricing", source_text: "AN3-13A qty 1 ea")
    @destination = { "country" => "US", "postal_code" => "10027" }
    clear_enqueued_jobs
  end

  def enqueue(**options)
    DistributorPricing::Run.enqueue(quote: @quote, expected_revision: @quote.reload.review_revision,
      destination: @destination, **options)
  end

  def held_output(text = @quote.source_text)
    { "schema" => "distributor_pricing/v1", "calculated_at" => Time.current.iso8601,
      "quote" => { "currency" => "USD", "total" => nil, "ready_lines" => 0, "held_lines" => 1 },
      "lines" => [{ "original_text" => text, "quantity" => "1", "unit" => "each",
        "catalog_item" => { "part_number" => "AN3-13A" },
        "pricing" => { "status" => "needs_procurement", "unit_price" => nil,
          "procurement_tasks" => ["TEST: obtain actual freight and five delivered competitors"] } }] }
  end

  def ready_output
    result = held_output
    expiry = (Time.current + 1.hour).iso8601
    result["quote"].merge!("total" => "2.00", "valid_until" => expiry, "ready_lines" => 1, "held_lines" => 0)
    result["lines"][0]["pricing"] = {
      "part_number" => "AN3-13A", "status" => "ready", "unit_price" => "2.00", "quote_total" => "2.00",
      "currency" => "USD", "quote_valid_until" => expiry, "calculated_at" => result["calculated_at"],
      "price_scope" => "delivered_ex_tax", "cost_breakdown" => { "total_cost" => "1.70" },
      "pricing_analysis" => { "realized_margin" => "0.15", "independent_benchmark_suppliers" => 5 },
      "selected_offer" => { "supplier" => "SYNTHETIC TEST supplier" },
      "procurement_plan" => { "supplier_offer_evidence" => { "source_url" => "https://test.example/offer" } }
    }
    result
  end

  def quote_line(**options)
    @quote.quote_lines.create!({ position: 1, original_text: @quote.source_text, description: "TEST AN bolt",
      catalog_sku: "AN3-13A", quantity: 1, quantity_unit: "each", state: "needs_buyer",
      unresolved_fields: ["unit_price"], spec: {} }.merge(options))
  end

  test "identical active posts deduplicate but completed checks refresh again" do
    run = nil
    assert_enqueued_jobs 1, only: PriceRfqJob do
      run = enqueue
      assert_equal run.id, enqueue.id
    end
    DistributorPricing::QuoteAgent.stub(:call, held_output) { PriceRfqJob.perform_now(run.id) }
    assert_equal "succeeded", run.reload.status
    assert_enqueued_jobs 1, only: PriceRfqJob do
      refute_equal run.id, enqueue.id
    end
  end

  test "changed revisions cannot enqueue and incomplete destinations are rejected" do
    assert_raises(Quote::StaleReview) do
      DistributorPricing::Run.enqueue(quote: @quote, expected_revision: "old", destination: @destination)
    end
    @destination["postal_code"] = ""
    assert_raises(DistributorPricing::Run::InputError) { enqueue }
    assert_equal 0, PricingRun.where(quote: @quote).count
  end

  test "agent receives complete email and attachment outside the quote lock" do
    @quote.update!(source_text: "AN3-13A qty 1 ea", source_bytes: "AN3-14A qty 2 ea", original_filename: "parts.txt")
    seen = nil
    callback = lambda do |**input|
      seen = input
      assert_equal "running", PricingRun.where(quote: @quote).order(id: :desc).first.status
      held_output
    end
    run = enqueue
    DistributorPricing::QuoteAgent.stub(:call, callback) { PriceRfqJob.perform_now(run.id) }
    assert_equal "AN3-13A qty 1 ea\nAN3-14A qty 2 ea", seen[:rfq]
    assert_equal @destination, seen[:destination]
    assert_equal "succeeded", run.reload.status
  end

  test "unreadable attachment holds the whole request without contacting agent" do
    @quote.update!(source_bytes: "TEST workbook", original_filename: "parts.xlsx")
    called = false
    run = enqueue
    DistributorPricing::QuoteAgent.stub(:call, ->(**_) { called = true }) { PriceRfqJob.perform_now(run.id) }
    refute called
    assert_equal "failed", run.reload.status
    assert_nil run.result
  end

  test "quote change while network is running rejects late result" do
    run = enqueue
    callback = ->(**_) { @quote.update!(title: "Changed while checking"); held_output }
    DistributorPricing::QuoteAgent.stub(:call, callback) { PriceRfqJob.perform_now(run.id) }
    assert_equal "stale", run.reload.status
    assert_nil run.result
  end

  test "ready exact unedited line applies through handoff and invalidates approval" do
    line = quote_line
    run = enqueue
    before = @quote.review_revision
    DistributorPricing::QuoteAgent.stub(:call, ready_output) { PriceRfqJob.perform_now(run.id) }
    assert_equal "succeeded", run.reload.status
    assert_equal BigDecimal("2.00"), line.reload.unit_price
    assert_equal [line.id], run.applied_line_ids
    assert run.output_available?(@quote.reload)
    refute_equal before, @quote.review_revision
    assert_nil @quote.approved_at
  end

  test "rep edits, unresolved specs, nonmatching specs and consolidated lines are preserved" do
    line = quote_line(unit_price: "9.00", price_source: "TEST previous source")
    [ { edited_fields: ["unit_price"] }, { unresolved_fields: ["grade", "unit_price"], edited_fields: [] },
      { unresolved_fields: ["unit_price"], edited_fields: [], spec: { "grade" => "Wrong grade" } } ].each do |attributes|
      line.update!(attributes)
      run = enqueue
      DistributorPricing::QuoteAgent.stub(:call, ready_output) { PriceRfqJob.perform_now(run.id) }
      assert_equal BigDecimal("9.00"), line.reload.unit_price
      assert_empty run.reload.applied_line_ids
    end
    line.update!(price_source: nil, edited_fields: [], unresolved_fields: ["unit_price"], spec: {})
    output = ready_output
    output["lines"][0]["original_lines"] = [{ "line_id" => "TEST-group" }]
    run = enqueue
    DistributorPricing::QuoteAgent.stub(:call, output) { PriceRfqJob.perform_now(run.id) }
    assert_equal BigDecimal("9.00"), line.reload.unit_price
    assert_empty run.reload.applied_line_ids
  end

  test "expired live prices cannot remain quotable approved or exportable" do
    line = quote_line
    run = enqueue
    DistributorPricing::QuoteAgent.stub(:call, ready_output) { PriceRfqJob.perform_now(run.id) }
    assert line.reload.quotable?
    @quote.reload.approve!(expected_revision: @quote.review_revision)
    assert @quote.approved?
    travel 2.hours do
      refute line.quotable?
      refute @quote.approved?
      refute @quote.approvable?
    end
  end

  test "source or price changes invalidate live pricing provenance" do
    line = quote_line
    run = enqueue
    DistributorPricing::QuoteAgent.stub(:call, ready_output) { PriceRfqJob.perform_now(run.id) }
    assert line.reload.quotable?
    @quote.update!(source_text: "AN3-13A qty 2 ea")
    refute line.quotable?
    refute @quote.approvable?
  end

  test "holds and non USD results never overwrite existing quote prices" do
    line = quote_line(unit_price: "9.00", price_source: "TEST previous source")
    [held_output, ready_output.tap { |output| output["quote"]["currency"] = "EUR" }].each do |output|
      run = enqueue
      DistributorPricing::QuoteAgent.stub(:call, output) { PriceRfqJob.perform_now(run.id) }
      assert_equal BigDecimal("9.00"), line.reload.unit_price
      assert_empty run.reload.applied_line_ids
    end
  end

  test "exceptions and credential fields are not persisted or exposed" do
    run = enqueue
    DistributorPricing::QuoteAgent.stub(:call, ->(**_) { raise "SECRET PROVIDER EXCEPTION" }) { PriceRfqJob.perform_now(run.id) }
    assert_equal "failed", run.reload.status
    refute_includes run.error_message, "SECRET"
    output = held_output.merge("api_key" => "TEST MUST NEVER STORE")
    refute PricingRun.valid_result?(output)
    refute PricingRun.valid_result?(ready_output.tap { |result| result["lines"][0]["pricing"]["pricing_analysis"]["independent_benchmark_suppliers"] = 4 })
  end

  test "safe display URLs reject scripts credentials insecure schemes and unusual ports" do
    ["javascript:alert(1)", "http://test.example", "https://user:secret@test.example/", "https://test.example:444", "https://test.example/\n"].each do |url|
      assert_nil PricingRun.safe_source_url(url)
    end
    assert_equal "https://test.example/part", PricingRun.safe_source_url("https://test.example/part")
  end
end
