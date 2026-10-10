# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/distributor_pricing/agent"

class DistributorAgentTest < Minitest::Test
  NOW = Time.utc(2026, 10, 10, 18, 0)

  class Markets
    attr_reader :calls
    def initialize(status: "available") = (@calls, @status = 0, status)
    def refresh
      @calls += 1
      { "refreshed_at" => NOW.iso8601, "series" => {} }
    end
    def for_item(_item, snapshot:) = { "status" => @status, "refreshed_at" => snapshot["refreshed_at"], "value" => "381.162", "is_finished_item_price" => false }
  end

  class Book
    attr_reader :calls
    def initialize(failure: false) = (@calls, @failure = 0, failure)
    def refresh(items:, request:)
      @calls += 1
      items.compact.to_h do |item|
        [item["part_number"], { "offers" => [], "public_market_prices" => [], "supplier_routes" => [],
                                "source_checks" => [{ "ok" => !@failure, "retrieved_at" => NOW.iso8601 }] }]
      end
    end
  end

  class Feed
    attr_reader :calls
    def initialize(stale: false, stock: 1_000, material: false)
      @calls, @stale, @stock, @material = 0, stale, stock, material
    end
    def refresh(request:)
      @calls += 1
      lines = request["items"].to_h do |item|
        source = evidence(item, request, "TEST acquisition supplier", "1.00")
        benchmark_a = evidence(item, request, "TEST dealer A", "3.00")
        benchmark_b = evidence(item, request, "TEST dealer B", "4.00")
        others = %w[C D E].map { |suffix| evidence(item, request, "TEST dealer #{suffix}", "4.00") }
        [item["line_id"], { "offers" => [source], "benchmarks" => [benchmark_a, benchmark_b] + others, "specifications_verified" => true,
                             "material_price_evidence" => @material ? { "request_id" => request["request_id"], "checked_at" => NOW.iso8601, "observation_date" => "2026-10-10", "source_url" => "https://test.example/material", "unit" => "USD/lb", "currency" => "USD", "value" => "1.5" } : nil }]
      end
      { "ok" => true, "request_id" => @stale ? "old-request" : request["request_id"], "checked_at" => NOW.iso8601, "lines" => lines }
    end
    def evidence(item, request, supplier, price)
      qty = BigDecimal(item["quantity"].to_s)
      {
        "id" => "#{item['line_id']}-#{supplier}", "supplier" => supplier, "part_number" => item["part_number"], "supplier_sku" => item["part_number"],
        "source_url" => "https://test.example/#{supplier.gsub(' ', '-')}/#{item['part_number']}",
        "quote_url" => "https://test.example/quote", "buy_url" => "https://test.example/buy",
        "retrieved_at" => NOW.iso8601, "revalidated_at" => NOW.iso8601, "revalidated_for_request_id" => request["request_id"],
        "valid_until" => (NOW + 3600).iso8601, "currency" => "USD", "unit" => item["unit"], "unit_price" => price,
        "pack_size" => "1", "minimum_quantity" => "1", "tier" => { "min" => "1", "max" => "10000" },
        "stock_quantity" => @stock.to_s, "stock_confirmed" => true, "lead_time_days" => 2, "destination" => request["destination"],
        "commercial_terms_verified" => true, "commercial_evidence" => "SYNTHETIC TEST commercial confirmation, not a live supplier quote",
        "specs" => item["specs"], "condition" => "new", "certifications" => [], "origin" => "US",
        "order_conditions" => { "line_sufficient" => true, "evidence" => "SYNTHETIC TEST no additional order conditions" },
        "costs" => DistributorPricing::Engine::COST_FIELDS.to_h { |field| [field, { "amount" => "0", "currency" => "USD", "evidence" => "SYNTHETIC TEST confirmed zero", "confirmed" => true }] },
        "payment_fee" => { "rate" => "0", "evidence" => "SYNTHETIC TEST fee waived", "confirmed" => true },
        "quantity" => item["quantity"], "total_price" => (qty * BigDecimal(price)).to_s("F"),
        "price_scope" => "delivered_ex_tax", "charge_scope" => "all_required_charges_ex_tax"
      }
    end
  end

  def agent(book: Book.new, markets: Markets.new, feed: Feed.new, gateway: nil)
    DistributorPricing::Agent.new(source_book: book, market_context: markets, supplier_feed: feed, gateway: gateway, clock: -> { NOW })
  end

  def quote(instance = agent, text = "AN3-13A qty 1 ea")
    instance.call(rfq: text, destination: { "country" => "US", "postal_code" => "10027" })
  end

  def test_complete_quote_from_confirmed_fresh_evidence
    result = quote
    assert_equal "priced_for_rep_review", result["status"]
    assert_equal "1.18", result.dig("quote", "total")
    assert_operator BigDecimal(result.dig("lines", 0, "pricing", "pricing_analysis", "realized_margin")), :>=, BigDecimal("0.15")
    assert result.dig("quote", "human_approval_required")
    refute result.dig("quote", "automatic_send")
    refute result.dig("quote", "purchased")
    assert_equal "supplier_confirmed", result.dig("lines", 0, "lead_time_estimate", "status")
    assert_equal 2, result.dig("lines", 0, "lead_time_estimate", "total_calendar_days")
  end

  def test_each_quote_fetches_sources_and_market_again
    book, markets, feed = Book.new, Markets.new, Feed.new
    instance = agent(book: book, markets: markets, feed: feed)
    first, second = quote(instance), quote(instance)
    refute_equal first.dig("request", "request_id"), second.dig("request", "request_id")
    assert_equal 2, book.calls
    assert_equal 2, markets.calls
    assert_equal 2, feed.calls
  end

  def test_destination_is_required
    result = agent.call(rfq: "AN3-13A qty 1 ea")
    assert_nil result.dig("quote", "total")
    assert_equal "needs_buyer", result.dig("lines", 0, "pricing", "status")
  end

  def test_old_feed_cannot_replay_a_prior_quote
    result = quote(agent(feed: Feed.new(stale: true)))
    assert_nil result.dig("quote", "total")
    assert_equal "needs_procurement", result.dig("lines", 0, "pricing", "status")
  end

  def test_live_material_failure_blocks_release
    result = quote(agent(markets: Markets.new(status: "unavailable")))
    assert_nil result.dig("quote", "total")
    assert_equal "needs_procurement", result.dig("lines", 0, "pricing", "status")
  end

  def test_live_public_source_failure_does_not_use_a_snapshot
    result = quote(agent(book: Book.new(failure: true)))
    assert_nil result.dig("quote", "total")
    assert_equal "needs_procurement", result.dig("lines", 0, "pricing", "status")
  end

  def test_no_commercial_feed_means_no_deliverable_quote
    result = quote(agent(feed: nil))
    assert_nil result.dig("quote", "total")
    assert_equal "needs_procurement", result.dig("lines", 0, "pricing", "status")
    assert_equal "needs_supplier_confirmation", result.dig("lines", 0, "lead_time_estimate", "status")
  end

  def test_public_dispatch_policy_is_only_a_partial_estimate_and_requires_quantity_stock
    source = { "dispatch_policy" => { "ok" => true, "verified_same_day_policy" => true, "retrieved_at" => NOW.iso8601 },
               "offers" => [{ "supplier" => "Aircraft Spruce", "stock_quantity" => 2, "source_url" => "https://test.example/stock" }] }
    result = DistributorPricing::LeadTime.for_line(pricing: {}, source: source, quantity: "1")
    assert_equal "partial_estimate", result["status"]
    assert_nil result["total_calendar_days"]
    refute result["is_delivery_commitment"]
    assert_equal "needs_supplier_confirmation", DistributorPricing::LeadTime.for_line(pricing: {}, source: source, quantity: "3")["status"]
  end

  def test_multiple_items_are_processed_separately
    result = quote(agent, "AN3-13A qty 1 ea; MS35206-203 qty 3 ea")
    assert_equal 2, result["lines"].size
    assert_equal 2, result["original_rfq_line_count"]
    assert_equal 2, result.dig("quote", "ready_lines")
  end

  def test_identical_items_are_consolidated_to_one_purchase_lot
    result = quote(agent, "AN3-13A qty 1 ea\nAN3-13A qty 2 ea")
    assert_equal 2, result["original_rfq_line_count"]
    assert_equal 1, result["priced_item_group_count"]
    assert_equal "3.0", result.dig("lines", 0, "quantity")
    assert_equal 2, result.dig("lines", 0, "original_lines").size
  end

  def test_missing_quantity_never_becomes_one
    result = quote(agent, "AN3-13A")
    assert_equal "needs_buyer", result.dig("lines", 0, "pricing", "status")
    assert_nil result.dig("quote", "total")
  end

  def test_requested_material_conflict_goes_to_buyer
    result = quote(agent, "AN3-13A qty 1 ea stainless steel")
    assert_equal "needs_buyer", result.dig("lines", 0, "pricing", "status")
    assert_nil result.dig("quote", "total")
  end

  def test_public_stock_cannot_override_confirmed_insufficient_stock
    result = quote(agent(feed: Feed.new(stock: 0)))
    assert_nil result.dig("quote", "total")
  end

  def test_empty_rfq_does_not_produce_a_zero_quote
    result = quote(agent, "Hello and thank you")
    assert_equal "intake_held", result["status"]
    assert_nil result.dig("quote", "total")
  end

  def test_unknown_requested_items_are_not_silently_dropped_from_a_complete_quote
    result = quote(agent, "AN3-13A qty 1 ea\nHYDRAULIC-PUMP-UNKNOWN qty 2 ea")
    assert_equal 2, result["lines"].size
    assert_nil result.dig("quote", "total")
    assert_equal "no_match", result.dig("lines", 1, "pricing", "status")
  end

  def test_requested_certifications_reach_the_live_procurement_adapter
    feed = Feed.new
    captured = nil
    wrapper = Object.new
    wrapper.define_singleton_method(:refresh) { |request:| captured = request; feed.refresh(request: request) }
    quote(agent(feed: wrapper), "AN3-13A qty 1 ea MTR required")
    assert_includes captured.dig("items", 0, "requirements", "certifications"), "MTR"
  end

  def test_bad_requests_fail_before_any_live_source_call
    book = Book.new
    instance = agent(book: book)
    assert_raises(ArgumentError) { instance.call(rfq: "AN3-13A qty 1 ea", requirements: "invalid") }
    assert_raises(ArgumentError) { instance.call(rfq: "AN3-13A qty 1 ea", currency: "usd") }
    assert_equal 0, book.calls
  end

  def test_weight_and_rudco_grade_are_retained
    parsed = DistributorPricing::Intake.new.parse(rfq: "2000 lb steel shot S-330")
    assert_equal "RC-STEELSHOT-S330", parsed.dig("lines", 0, "item", "part_number")
    assert_equal "lb", parsed.dig("lines", 0, "unit")
    assert_equal "2000", parsed.dig("lines", 0, "quantity")
  end
end
