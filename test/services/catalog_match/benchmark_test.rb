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

class CatalogMatch::MetalsObservationsTest < ActiveSupport::TestCase
  ITEM = "RC-SS304-SHT-16GA-48X96-4".freeze

  def observation(supplier:, price:, finish: "#4", thickness: 0.063)
    { "pn" => ITEM, "supplier" => supplier, "source_url" => "https://example.test/#{supplier}", "observed_at" => "2026-10-10T19:00:00Z",
      "unit_price_usd" => price, "sale_unit" => "each", "grade" => "304", "finish" => finish, "thickness_in" => thickness,
      "width_in" => 48, "length_in" => 96 }
  end

  teardown { CatalogMatch::MetalsObservations.reset! }

  test "one listing is a reference, not a price" do
    CatalogMatch::MetalsObservations.observations = [ observation(supplier: "Zoro", price: 1025.99) ]
    item = CatalogMatch::Catalog.default.find(ITEM)
    assert_nil CatalogMatch::Benchmark.for(item)
    assert_equal 1, CatalogMatch::Benchmark.references(item).size
  end

  test "two independent listings of the exact spec price the row at their midpoint" do
    CatalogMatch::MetalsObservations.observations = [
      observation(supplier: "Zoro", price: 1025.99), observation(supplier: "MetalsDepot", price: 980.00),
      observation(supplier: "Other", price: 500.00, finish: "2B"), observation(supplier: "Thick", price: 400.00, thickness: 0.075)
    ]
    price = CatalogMatch::Benchmark.for(CatalogMatch::Catalog.default.find(ITEM))
    assert_equal BigDecimal("1003.00"), price["unit_price"]
    assert_equal "public_listing_midpoint", price["benchmark"]["kind"]
    assert_match(/Zoro, MetalsDepot/, price["price_source"])
  end

  test "the checked-in observations file loads and prices nothing until two suppliers agree" do
    item = CatalogMatch::Catalog.default.find(ITEM)
    assert_operator CatalogMatch::Benchmark.references(item).size, :>=, 1
  end
end
