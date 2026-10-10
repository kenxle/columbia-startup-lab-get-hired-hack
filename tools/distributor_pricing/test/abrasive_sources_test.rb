# frozen_string_literal: true
require "minitest/autorun"
require_relative "../lib/distributor_pricing/source_book"
require_relative "../lib/distributor_pricing/catalog"

class AbrasiveSourcesTest < Minitest::Test
  A = DistributorPricing::AbrasiveSources
  ITEM = { "part_number" => "RC-STEELSHOT-S330", "material" => "steel shot", "grade" => "S330" }.freeze
  def route(parser, item = ITEM)
    A.routes(item).find { |r| r["parser"] == parser }
  end
  def kleen(price = "72.50")
    "<h1>Item # SS50330, Cast Steel Shot - S330 50lb Bag</h1><h3>Price</h3> $#{price}"
  end
  def test_exact_identity_and_package_required
    assert_equal "72.5", A.price("Cart $9.00 " + kleen, route("kleen"))["unit_price"]
    assert_nil A.price("Cart $9.00 " + kleen.sub("S330 50", "S170 50"), route("kleen"))
    assert_equal "72.5", A.price(kleen, route("kleen"))["unit_price"]
    assert_nil A.price(kleen.sub("S330 50", "S170 50"), route("kleen"))
    assert_nil A.price(kleen.sub("50lb", "25lb"), route("kleen"))
    assert_nil A.price(kleen.sub("50lb Bag", "Bag"), route("kleen"))
  end
  def test_actual_rudco_catalog_routes
    catalog = DistributorPricing::Catalog.new
    %w[RC-STEELSHOT-S330 RC-STEELSHOT-S170 RC-STEELGRIT-G40 RC-STEELGRIT-G25].each do |part|
      item = catalog.find(part)
      refute_nil item
      assert_equal part.include?("SHOT") ? 3 : 2, A.routes(item).size
    end
    assert_empty A.routes(ITEM.merge("material" => "steel sheet"))
    assert_empty A.routes(catalog.find("RC-STAINLESSSTEELGRIT-G25"))
  end
  def test_precision_keeps_published_package_tiers
    html = '<h1>Stock No. SS-330, Steel Shot</h1>List Price $62.00 Package Discount Price / % 4 - 9 $58.00 10 &nbsp; and&nbsp;up $54.50 Packaging N/A 50 lb. bag'
    result = A.price(html, route("precision"))
    assert_equal "62.0", result["unit_price"]
    assert_equal [{ "min" => "4", "max" => "9", "unit_price" => "58.0" }, { "min" => "10", "max" => nil, "unit_price" => "54.5" }], result["published_tiers"]
    assert_nil A.price(html.sub("50 lb.", "20 kg"), route("precision"))
  end
  def test_ruddock_exact_row_and_ton_exclusion
    html = 'SKU: ABR-011 Our Steel Shot is packaged in 50 lb. bags.<table><tr><td>SKU</td><td>1-9 BAGS</td><td>10-19 BAGS</td><td>1 TON BAGS</td></tr><tr><td>S-330</td><td>$57.00</td><td>$52.00</td><td>$40.00</td></tr></table>'
    result = A.price(html, route("ruddock"))
    assert_equal %w[57.0 52.0], result["published_tiers"].map { |t| t["unit_price"] }
    assert_nil A.price(html.sub("S-330", "S-170"), route("ruddock"))
    assert_nil A.price(html.sub("50 lb. bags", "bulk"), route("ruddock"))
  end
  def test_grit_catalog_row_is_scoped
    item = ITEM.merge("grade" => "G25", "material" => "steel grit")
    html = '<table><tr><td>SG5040</td><td>G40 50lb Bag</td><td>$11.00</td></tr><tr><td>SG5025</td><td>G25 50lb Bag</td><td>$77.00</td></tr></table>'
    assert_equal "77.0", A.price(html, route("kleen", item))["unit_price"]
    assert_nil A.price(html.sub("G25 50lb", "G40 50lb"), route("kleen", item))
  end
  def test_each_run_fetches_again_and_never_emits_executable_offer
    http = Object.new
    http.instance_variable_set(:@body, kleen)
    http.instance_variable_set(:@calls, [])
    def http.get(url)
      @calls << url
      { "ok" => true, "body" => url.include?("kleenblast") ? @body : "", "retrieved_at" => Time.now.utc.iso8601 }
    end
    book = DistributorPricing::SourceBook.new(http_client: http)
    first = book.refresh(items: [ITEM], request: { "request_id" => "a" }).fetch(ITEM["part_number"])
    http.instance_variable_set(:@body, kleen("81.00"))
    second = book.refresh(items: [ITEM], request: { "request_id" => "b" }).fetch(ITEM["part_number"])
    assert_empty first["offers"]
    assert_empty second["offers"]
    assert_equal "72.5", first["public_market_prices"].first["unit_price"]
    assert_equal "81.0", second["public_market_prices"].first["unit_price"]
    refute second["public_market_prices"].first["usable_as_delivered_benchmark"]
    assert_equal route("kleen")["source_url"], second["public_market_prices"].first["buy_url"]
    assert_equal 2, http.instance_variable_get(:@calls).count(route("kleen")["source_url"])
    http.instance_variable_set(:@body, kleen.sub("50lb", "25lb"))
    third = book.refresh(items: [ITEM], request: { "request_id" => "c" }).fetch(ITEM["part_number"])
    assert_empty third["public_market_prices"]
  end
end
