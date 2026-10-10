require "test_helper"

class CatalogMatch::BenchmarkTest < ActiveSupport::TestCase
  test "a RudCo row carries its website list price, dated and labeled as a list price" do
    price = CatalogMatch::Benchmark.for(CatalogMatch::Catalog.default.find("RC-STEELSHOT-S330"))
    assert_equal BigDecimal("0.40"), price["unit_price"]
    assert_equal "USD", price["currency"]
    assert_equal "website_list_price", price["benchmark"]["kind"]
    assert_match(/\A2026-10-10/, price["benchmark"]["as_of"])
    assert_match(/not a quote/, price["benchmark"]["explanation"])
  end

  test "an aviation row carries the two-dealer midpoint" do
    price = CatalogMatch::Benchmark.for(CatalogMatch::Catalog.default.find("AN3-13A"))
    assert_equal BigDecimal("0.565"), price["unit_price"]
    assert_equal "dealer_listing_midpoint", price["benchmark"]["kind"]
  end

  test "a metals row has no price, and the contract says so" do
    assert_nil CatalogMatch::Benchmark.for(CatalogMatch::Catalog.default.find("RC-SS304-SHT-16GA-48X96-2B"))
    result = CatalogMatch::Contract.call({ "line_text" => "304 SS sheet 16ga 4x8" })
    assert result["candidates"].all? { |candidate| candidate["price"].nil? }
    priced = CatalogMatch::Contract.call({ "line_text" => "40,000 lb S-330 steel shot" })
    assert_equal "0.4", priced["best"]["price"]["unit_price"]
  end
end
