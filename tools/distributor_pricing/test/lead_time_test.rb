# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/distributor_pricing/lead_time"

class DistributorLeadTimeTest < Minitest::Test
  def estimate(days, verified: true, stock: true)
    offer = { "lead_time_days" => days, "commercial_terms_verified" => verified,
      "stock_confirmed" => stock, "supplier" => "SYNTHETIC TEST supplier",
      "quote_url" => "https://test.example/quote", "retrieved_at" => "2026-10-11T17:00:00Z" }
    DistributorPricing::LeadTime.for_line(pricing: { "procurement_plan" => { "supplier_offer_evidence" => offer } }, source: {}, quantity: "1")
  end

  def test_verified_integer_strings_preserve_supplier_timing
    [2, "2", "02", "0"].each do |value|
      result = estimate(value)
      assert_equal "supplier_confirmed", result["status"]
      assert_equal value.to_i, result["total_calendar_days"]
      refute result["is_delivery_commitment"]
    end
  end

  def test_invalid_or_fractional_timing_stays_unknown
    [nil, true, -1, "-1", 2.5, "2.5", "2e1", " 2", "2 days"].each do |value|
      result = estimate(value)
      assert_equal "needs_supplier_confirmation", result["status"]
      assert_nil result["total_calendar_days"]
    end
  end

  def test_numeric_timing_without_commercial_or_stock_confirmation_stays_unknown
    assert_equal "needs_supplier_confirmation", estimate("2", verified: false)["status"]
    assert_equal "needs_supplier_confirmation", estimate("2", stock: false)["status"]
  end
end
