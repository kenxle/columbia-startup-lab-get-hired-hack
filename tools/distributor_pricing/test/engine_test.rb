# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/distributor_pricing/engine"

class DistributorPricingEngineTest < Minitest::Test
  NOW = Time.utc(2026, 10, 10, 16)

  def setup
    # Two-source fixtures isolate financial math; production defaults to five.
    @engine = DistributorPricing::Engine.new(policy: DistributorPricing::Policy.new(minimum_benchmark_suppliers: 2))
    @destination = { "country" => "US", "postal_code" => "10027" }
    @item = { "part_number" => "AN3-5A", "condition" => "new", "specs" => { "material" => "steel" } }
    @offer = {
      "id" => "supplier-quote-1", "supplier" => "Supplier A", "part_number" => "AN3-5A", "supplier_sku" => "A-123",
      "source_url" => "https://supplier.example/product/123", "quote_url" => "https://supplier.example/quotes/1",
      "buy_url" => "https://supplier.example/cart/123", "retrieved_at" => (NOW - 3600).iso8601,
      "valid_until" => (NOW + 3600 * 12).iso8601, "currency" => "USD", "unit" => "each", "unit_price" => "10.00",
      "pack_size" => 1, "minimum_quantity" => 1, "tier" => { "min" => 1, "max" => nil },
      "stock_quantity" => 100, "stock_confirmed" => true, "lead_time_days" => 2, "destination" => @destination,
      "commercial_terms_verified" => true, "commercial_evidence" => "Operator verified supplier quote Q1",
      "condition" => "new", "specs" => { "material" => "steel" }, "certifications" => ["COC"], "origin" => "US",
      "order_conditions" => { "line_sufficient" => true, "evidence" => "Q1 has no order minimum or other line dependency" },
      "costs" => DistributorPricing::Engine::COST_FIELDS.to_h { |field| [field, { "amount" => "0.00", "currency" => "USD", "confirmed" => true, "evidence" => "Q1 confirms zero #{field}" }] },
      "payment_fee" => { "rate" => "0", "confirmed" => true, "evidence" => "Confirmed fee-free bank transfer" }
    }
    @benchmarks = [benchmark("Market A", "140.00"), benchmark("Market B", "160.00")]
  end

  def benchmark(supplier, total)
    @offer.merge("id" => supplier, "supplier" => supplier, "quantity" => 10,
                 "total_price" => total, "price_scope" => "delivered_ex_tax", "charge_scope" => "all_required_charges_ex_tax")
  end

  def test_production_policy_requires_five_independent_competitors_per_item
    @engine = DistributorPricing::Engine.new
    assert_equal 5, @engine.instance_variable_get(:@policy).minimum_benchmark_suppliers
    assert_held price, /5 independent suppliers/
    five = %w[A B C D E].map { |name| benchmark(name, "150") }
    result = price(benchmarks: five)
    assert_equal "ready", result["status"]
    assert_equal 5, result.dig("pricing_analysis", "independent_benchmark_suppliers")
    assert_held price(benchmarks: five.first(4) + [five.first]), /5 independent suppliers/
  end

  def price(**overrides)
    @engine.price_line(**{ item: @item, quantity: 10, unit: "each", destination: @destination,
                         offers: [@offer], benchmarks: @benchmarks, now: NOW }.merge(overrides))
  end

  def assert_held(result, reason)
    assert_nil result["unit_price"]
    refute_equal "ready", result["status"]
    assert_match reason, result["reasons"].join(" ")
  end

  def test_target_uses_gross_margin_and_decimal_money
    result = price
    assert_equal "ready", result["status"]
    assert_equal "11.77", result["unit_price"]
    assert_equal "117.70", result["quote_total"]
    assert_equal "100.00", result.dig("cost_breakdown", "product_acquisition")
    assert_equal "10.87", result.dig("pricing_analysis", "minimum_unit_price")
    assert_operator BigDecimal(result.dig("pricing_analysis", "realized_margin")), :>=, BigDecimal("0.15")
    assert_equal @offer["source_url"], result.dig("procurement_plan", "supplier", "source_url")
    assert_equal @offer["valid_until"], result["quote_valid_until"]
  end

  def test_all_explicit_line_costs_are_included
    @offer["costs"].each_value { |cost| cost["amount"] = "1.01" }
    result = price
    assert_equal "107.07", result.dig("cost_breakdown", "total_before_payment_fee")
    assert_equal "12.60", result["unit_price"]
  end

  def test_fee_on_revenue_and_rounded_fee_do_not_break_floor
    @offer["payment_fee"]["rate"] = "0.029"
    @offer["unit_price"] = "0.07"
    result = price(quantity: 1, benchmarks: [benchmark("M1", "1").merge("quantity" => 1), benchmark("M2", "1").merge("quantity" => 1)])
    assert_equal "0.10", result["unit_price"]
    assert_equal "0.01", result.dig("cost_breakdown", "payment_fee")
    assert_equal "0.2", result.dig("pricing_analysis", "realized_margin")
  end

  def test_fee_enters_margin_denominator
    @offer["payment_fee"]["rate"] = "0.03"
    result = price
    assert_equal "12.20", result["unit_price"]
    assert_equal "3.66", result.dig("cost_breakdown", "payment_fee")
    assert_operator BigDecimal(result.dig("pricing_analysis", "realized_margin")), :>=, BigDecimal("0.15")
  end

  def test_reduces_to_median_above_minimum_without_claiming_cheapest
    result = price(benchmarks: [benchmark("A", "100"), benchmark("B", "125")])
    assert_equal "ready", result["status"]
    assert_equal "11.25", result["unit_price"]
    assert_equal "11.25", result.dig("pricing_analysis", "market_median_unit_price")
    assert_equal false, result.dig("pricing_analysis", "at_or_below_market_low")
    assert_equal true, result.dig("pricing_analysis", "competitive")
    assert_operator BigDecimal(result.dig("pricing_analysis", "realized_margin")), :>=, BigDecimal("0.08")
  end

  def test_floor_above_market_holds_firm_quote
    result = price(benchmarks: [benchmark("A", "100"), benchmark("B", "110")])
    assert_equal "not_competitive", result["status"]
    assert_held result, /minimum-margin floor/
    assert_equal false, result.dig("pricing_analysis", "competitive")
    assert_equal "10.87", result.dig("pricing_analysis", "minimum_unit_price")
  end

  def test_selects_cheapest_feasible_acquisition_and_skips_unconfirmed_cheaper_offer
    cheap = Marshal.load(Marshal.dump(@offer)).merge("id" => "unconfirmed", "unit_price" => "1.00", "stock_confirmed" => false)
    medium = @offer.merge("id" => "medium", "unit_price" => "9.00")
    result = price(offers: [@offer, cheap, medium])
    assert_equal "medium", result.dig("selected_offer", "id")
    assert_equal "10.59", result["unit_price"]
    assert_equal 3, result["offer_assessments"].length
  end

  def test_pack_overbuy_and_moq_are_fully_charged
    @offer.merge!("pack_size" => 6, "minimum_quantity" => 13, "unit_price" => "1.00")
    result = price
    assert_equal 18, result.dig("cost_breakdown", "purchase_quantity")
    assert_equal 8, result.dig("cost_breakdown", "surplus_quantity")
    assert_equal "18.00", result.dig("cost_breakdown", "product_acquisition")
    assert_equal "2.12", result["unit_price"]
  end

  def test_quantity_tier_covers_purchase_quantity_not_only_requested_quantity
    @offer.merge!("pack_size" => 6, "tier" => { "min" => 1, "max" => 10 })
    assert_held price, /price tier/
    assert_nil price["indicative_product_only_price"]
  end

  def test_unknown_upper_tier_is_different_from_explicit_unbounded_tier
    @offer["tier"].delete("max")
    assert_held price, /price tier/
  end

  def test_stock_must_cover_purchased_packs
    @offer.merge!("pack_size" => 6, "stock_quantity" => 10)
    assert_held price, /sufficient stock/
  end

  def test_public_listing_is_indicative_only
    @offer["commercial_terms_verified"] = false
    result = price
    assert_held result, /commercial terms/
    assert_equal "10.00", result.dig("indicative_product_only_price", "unit_price")
    assert_equal false, result.dig("indicative_product_only_price", "is_selling_quote")
  end

  def test_each_unknown_cost_blocks_and_is_not_coerced_to_zero
    DistributorPricing::Engine::COST_FIELDS.each do |field|
      changed = Marshal.load(Marshal.dump(@offer))
      changed["costs"][field]["amount"] = nil
      result = price(offers: [changed])
      assert_held result, /#{field}/
      assert_nil result.dig("offer_assessments", 0, "cost_breakdown", field)
    end
  end

  def test_zero_needs_confirmation_evidence_and_currency
    %w[evidence confirmed currency].each do |key|
      changed = Marshal.load(Marshal.dump(@offer))
      changed["costs"]["inbound_freight"].delete(key)
      assert_held price(offers: [changed]), /inbound_freight/
    end
  end

  def test_fee_is_not_defaulted_to_zero
    @offer.delete("payment_fee")
    assert_held price, /payment fee/
  end

  def test_order_conditions_cannot_be_solved_by_a_line_in_isolation
    @offer["order_conditions"]["line_sufficient"] = false
    assert_held price, /multi-line conditions/
  end

  def test_stale_and_future_sources_cannot_even_be_indicative
    [NOW - 86_400, NOW + 1].each do |time|
      result = price(offers: [@offer.merge("retrieved_at" => time.iso8601)])
      assert_held result, /timestamp/
      assert_nil result["indicative_product_only_price"]
    end
  end

  def test_expired_quote_is_held
    result = price(offers: [@offer.merge("valid_until" => NOW.iso8601)])
    assert_held result, /expiry/
    assert_nil result["indicative_product_only_price"]
  end

  def test_missing_destination_and_quantity_require_buyer
    result = price(destination: nil, quantity: nil)
    assert_equal "needs_buyer", result["status"]
    assert_equal 2, result["buyer_questions"].size
    assert_empty result["procurement_tasks"]
    assert_nil result["quote_total"]
  end

  def test_fractional_piece_quantity_requires_buyer
    assert_equal "needs_buyer", price(quantity: "1.5")["status"]
  end

  def test_destination_mismatch_is_procurement_not_buyer
    @offer["destination"] = { "country" => "US", "postal_code" => "90210" }
    result = price
    assert_held result, /destination/
    assert_empty result["buyer_questions"]
  end

  def test_unknown_lead_time_and_unachievable_deadline
    assert_held price(offers: [@offer.merge("lead_time_days" => nil)]), /lead time/
    assert_held price(delivery_by: (NOW + 86_400).iso8601), /deadline/
  end

  def test_delivery_deadline_caps_acceptance_time
    result = price(delivery_by: (NOW + 2 * 86_400 + 600).iso8601)
    assert_equal (NOW + 600).iso8601, result["quote_valid_until"]
  end

  def test_same_instant_delivery_slack_is_not_releasable
    result = price(delivery_by: (NOW + 2 * 86_400).iso8601)
    assert_held result, /no time to accept/
  end

  def test_condition_spec_certification_and_origin_mismatches
    assert_held price(offers: [@offer.merge("condition" => "used")]), /condition/
    assert_held price(offers: [@offer.merge("specs" => { "material" => "aluminum" })]), /Specification/
    assert_held price(requirements: { "certifications" => ["FAA 8130-3"] }), /certifications/
    assert_held price(requirements: { "allowed_origins" => ["CA"] }), /Origin/
  end

  def test_unsafe_substitution_never_becomes_indicative
    result = price(offers: [@offer.merge("part_number" => "AN3-5")])
    assert_held result, /substitution/
    assert_nil result["indicative_product_only_price"]
  end

  def test_product_only_market_prices_do_not_establish_delivered_competitiveness
    result = price(benchmarks: @benchmarks.map { |benchmark| benchmark.merge("price_scope" => "product_only") })
    assert_held result, /2 independent suppliers/
    assert_equal "11.77", result.dig("pricing_analysis", "target_unit_price")
    assert result["benchmark_comparisons"].all? { |benchmark| !benchmark["comparable"] }
  end

  def test_benchmark_requires_matching_quantity_currency_and_unit
    [{ "quantity" => 1 }, { "currency" => "EUR" }, { "unit" => "pack" }].each do |change|
      assert_held price(benchmarks: @benchmarks.map { |benchmark| benchmark.merge(change) }), /2 independent suppliers/
    end
  end

  def test_two_quotes_from_same_supplier_are_not_independent
    assert_held price(benchmarks: [benchmark("Market", "140"), benchmark(" market ", "160")]), /2 independent suppliers/
  end

  def test_duplicate_supplier_rows_do_not_weight_median
    result = price(benchmarks: [benchmark("A", "120"), benchmark("A", "120"), benchmark("B", "180")])
    assert_equal "15.0", result.dig("pricing_analysis", "market_median_unit_price")
    assert_equal 2, result.dig("pricing_analysis", "independent_benchmark_suppliers")
  end

  def test_absent_market_is_held_without_fabricated_prices
    result = price(benchmarks: [])
    assert_held result, /2 independent suppliers/
    assert_nil result.dig("pricing_analysis", "competitive")
    empty = price(offers: [], benchmarks: [])
    assert_held empty, /Obtain an exact-part/
    assert_nil empty["indicative_product_only_price"]
  end

  def test_benchmark_freshness_caps_quote_validity
    changed = @benchmarks.map { |benchmark| benchmark.merge("retrieved_at" => (NOW - 86_000).iso8601) }
    assert_equal (NOW + 400).iso8601, price(benchmarks: changed)["quote_valid_until"]
  end

  def test_invalid_numeric_values_are_held
    %w[NaN Infinity -1 nonsense].each do |value|
      assert_held price(offers: [@offer.merge("unit_price" => value)]), /positive supplier/
    end
  end

  def test_policy_rejects_invalid_margin_and_windows
    assert_raises(ArgumentError) { DistributorPricing::Policy.new(target_margin: "0.07") }
    assert_raises(ArgumentError) { DistributorPricing::Policy.new(minimum_margin: "NaN") }
    assert_raises(ArgumentError) { DistributorPricing::Policy.new(quote_validity_seconds: 0) }
  end

  def test_engine_does_not_mutate_inputs_and_is_repeatable
    before = Marshal.dump([@offer, @benchmarks, @item, @destination])
    assert_equal price, price
    assert_equal before, Marshal.dump([@offer, @benchmarks, @item, @destination])
  end

  def test_conflicting_catalog_and_buyer_specs_are_not_silently_overwritten
    changed = @offer.merge("specs" => { "material" => "aluminum" })
    assert_held price(offers: [changed], requirements: { "specs" => { "material" => "aluminum" } }), /Specification/
  end

  def test_benchmark_out_of_stock_or_unresolved_order_is_not_comparable
    [{ "stock_confirmed" => false }, { "stock_quantity" => 1 }, { "order_conditions" => nil }].each do |change|
      assert_held price(benchmarks: @benchmarks.map { |benchmark| benchmark.merge(change) }), /2 independent suppliers/
    end
  end

  def test_cost_fee_and_quantity_rounding_preserve_margin_across_small_values
    %w[0.01 0.07 1.001 7.99].product(%w[0 0.029 0.1], [1, 3, 10]).each do |unit_cost, fee_rate, qty|
      changed = Marshal.load(Marshal.dump(@offer))
      changed["unit_price"] = unit_cost
      changed["payment_fee"]["rate"] = fee_rate
      market = [benchmark("A", "500"), benchmark("B", "600")].map { |row| row.merge("quantity" => qty) }
      result = price(offers: [changed], benchmarks: market, quantity: qty)
      assert_equal "ready", result["status"]
      revenue = BigDecimal(result["quote_total"])
      cost = BigDecimal(result.dig("cost_breakdown", "total_cost"))
      assert_operator (revenue - cost) / revenue, :>=, BigDecimal("0.15")
    end
  end

  def test_cheapest_offer_full_evidence_is_selected_even_with_duplicate_source_ids
    changed = @offer.merge("unit_price" => "9.00", "commercial_evidence" => "Revised quote")
    result = price(offers: [@offer, changed])
    assert_equal "Revised quote", result.dig("procurement_plan", "commercial_evidence")
  end

  def test_policy_window_caps_quote_validity
    @engine = DistributorPricing::Engine.new(policy: DistributorPricing::Policy.new(quote_validity_seconds: 120, minimum_benchmark_suppliers: 2))
    assert_equal (NOW + 120).iso8601, price["quote_valid_until"]
  end

  def test_invalid_source_url_cannot_ground_a_price
    assert_held price(offers: [@offer.merge("source_url" => "javascript:alert(1)")]), /HTTP/
  end

  def test_missing_cost_and_condition_containers_fail_closed
    assert_held price(offers: [@offer.merge("costs" => nil, "condition" => nil)]), /condition/
    assert_held price(offers: [nil]), /part number/
  end

  def test_fractional_weight_buys_whole_packs_and_spreads_all_acquisition_cost
    @offer.merge!("unit" => "lb", "unit_price" => "1", "pack_size" => "5", "minimum_quantity" => "0.5")
    @benchmarks.each { |row| row.merge!("unit" => "lb", "quantity" => "12.5") }
    result = price(unit: "lb", quantity: "12.5")
    assert_equal "ready", result["status"]
    assert_equal 15, result.dig("cost_breakdown", "purchase_quantity")
    assert_equal "12.5", result.dig("cost_breakdown", "requested_quantity")
    assert_equal "2.5", result.dig("cost_breakdown", "surplus_quantity")
    assert_equal "15.00", result.dig("cost_breakdown", "product_acquisition")
    assert_equal "1.42", result["unit_price"]
    assert_equal "17.75", result["quote_total"]
  end

  def test_decimal_pack_and_stock_math_has_no_float_ceiling_error
    @offer.merge!("unit" => "kg", "unit_price" => "1", "pack_size" => "0.1", "minimum_quantity" => "0.1",
                  "stock_quantity" => "0.3", "tier" => { "min" => "0.1", "max" => "0.3" })
    @benchmarks.each { |row| row.merge!("unit" => "kg", "quantity" => "0.3", "pack_size" => "0.1", "minimum_quantity" => "0.1", "tier" => { "min" => "0.1", "max" => "0.3" }) }
    result = price(unit: "kg", quantity: "0.3")
    assert_equal "ready", result["status"]
    assert_equal "0.3", result.dig("cost_breakdown", "purchase_quantity")
    assert_equal 0, result.dig("cost_breakdown", "surplus_quantity")
    assert_equal "0.36", result["quote_total"]
  end

  def test_fractional_line_revenue_and_payment_fee_are_rounded_consistently
    @offer.merge!("unit" => "m", "unit_price" => "1", "pack_size" => "0.1", "minimum_quantity" => "0.1")
    @offer["payment_fee"]["rate"] = "0.03"
    @benchmarks.each { |row| row.merge!("unit" => "m", "quantity" => "12.5") }
    result = price(unit: "m", quantity: "12.5")
    assert_equal "15.25", result["quote_total"]
    assert_equal "0.46", result.dig("cost_breakdown", "payment_fee")
    revenue, cost = BigDecimal(result["quote_total"]), BigDecimal(result.dig("cost_breakdown", "total_cost"))
    assert_operator (revenue - cost) / revenue, :>=, BigDecimal("0.15")
    assert_equal ((revenue - cost) / revenue).round(8, BigDecimal::ROUND_FLOOR).to_s("F"), result.dig("pricing_analysis", "realized_margin")
  end

  def test_nonrecoverable_tax_is_required_and_not_assumed_exempt
    @offer["costs"].delete("nonrecoverable_tax")
    assert_held price, /nonrecoverable_tax/
  end

  def test_count_unit_pack_and_stock_cannot_be_fractional
    assert_held price(offers: [@offer.merge("pack_size" => "1.5")]), /pack size/
    assert_held price(offers: [@offer.merge("stock_quantity" => "10.5")]), /sufficient stock/
  end
end

