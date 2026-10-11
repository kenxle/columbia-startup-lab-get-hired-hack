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

  def test_binary_utf8_page_keeps_exact_price_and_does_not_mutate_source_bytes
    body = (kleen.sub("50lb", "50\u00a0lb") + " © Supplier").b.freeze
    result = A.price(body, route("kleen"))
    assert_equal "72.5", result["unit_price"]
    assert_equal "1.45", result["normalized_unit_price"]
    assert_equal Encoding::BINARY, body.encoding
    assert_equal " © Supplier".b, body.byteslice(-12, 12)
    assert_nil A.price(body.sub("50".b, "25".b), route("kleen"))
  end

  def test_invalid_or_oversized_bytes_never_repair_a_price_into_evidence
    assert_nil A.price(kleen.sub("72.50", "72\xFF.50".b).b, route("kleen"))
    assert_nil A.price(kleen.b + "\xA9".b, route("kleen"))
    assert_nil A.price(kleen + " " * A::MAX_HTML_BYTES, route("kleen"))
    assert_nil A.price(nil, route("kleen"))
  end

  def test_invalid_binary_source_returns_unverified_listing_without_aborting_refresh
    http = Object.new
    body = kleen.b + "\xFF".b
    http.define_singleton_method(:get) do |url|
      {"ok" => true, "body" => body, "retrieved_at" => Time.now.utc.iso8601}
    end
    result = DistributorPricing::SourceBook.new(http_client: http).refresh(items: [ITEM], request: {"request_id" => "invalid-bytes"}).fetch(ITEM["part_number"])
    assert_empty result["offers"]
    assert_empty result["public_market_prices"]
    assert result["source_checks"].any? { |check| check["listing_status"] == "price_or_specification_not_verified" }
  end
  def test_actual_rudco_catalog_routes
    catalog = DistributorPricing::Catalog.new
    %w[RC-STEELSHOT-S330 RC-STEELSHOT-S170 RC-STEELGRIT-G40 RC-STEELGRIT-G25].each do |part|
      item = catalog.find(part)
      refute_nil item
      assert_equal 3, A.routes(item).size
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

  def new_source(parser)
    route(parser, ITEM.merge("material" => "steel grit", "grade" => parser == "national" ? "G40" : "G25"))
  end

  def new_html(parser, changes = {}, variants: nil)
    r = new_source(parser)
    product = { "@type" => "Product", "url" => r["source_url"], "sku" => r["supplier_sku"],
      "name" => "Steel Grit 50 lb Bag G40", "description" => "50 lbs Bag Part: 4000 (25 Steel Grit)",
      "offers" => { "@type" => "Offer", "url" => r["source_url"], "priceCurrency" => "USD", "price" => "67.89" } }
    product["offers"] = [product["offers"].merge("price" => "123")] if parser == "americanhawk"
    product.merge!(changes)
    html = '<script type="application/ld+json">' + JSON.generate(product) + '</script>'
    if parser == "americanhawk"
      variants ||= [{ "sku" => "4001", "attributes" => { "attribute_pa_bags" => "g-50-steel-grit" }, "display_price" => 999 },
                    { "sku" => "4000", "attributes" => { "attribute_pa_bags" => "g-25-steel-grit" }, "display_price" => 123 }]
      html += '<form action="' + r["source_url"] + '" data-product_variations="' + CGI.escapeHTML(JSON.generate(variants)) + '">'
    end
    html
  end

  def test_new_sources_require_bound_currency_package_and_valid_json
    %w[national americanhawk].each do |parser|
      r = new_source(parser)
      html = new_html(parser)
      refute_nil A.price(html, r)
      assert_nil A.price(html.gsub("USD", "CAD"), r)
      assert_nil A.price(html.gsub("50 lb", "25 lb"), r)
      assert_nil A.price(html.gsub(r["supplier_sku"], "wrong-sku"), r)
      assert_nil A.price('<script type="application/ld+json">{broken</script>', r)
      assert_nil A.price(html.gsub(r["source_url"], "https://example.com/wrong"), r)
    end
  end

  def test_national_price_is_product_offer_only
    r = new_source("national")
    html = new_html("national")
    assert_equal "67.89", A.price('Cart $1.00 ' + html, r)["unit_price"]
    assert_nil A.price(html.sub('"67.89"', '"-1"'), r)
    assert_nil A.price(html.sub('"67.89"', '"Infinity"'), r)
    assert_nil A.price(html.gsub("G40", "G25"), r)
    assert_nil A.price(html + html, r)
    refute A.price(html, r)["stock_confirmed"]
  end

  def test_americanhawk_selects_exact_variant_and_rejects_duplicates
    r = new_source("americanhawk")
    html = new_html("americanhawk")
    assert_equal "123.0", A.price(html, r)["unit_price"]
    assert_nil A.price(html.gsub("g-25-steel-grit", "g-50-steel-grit"), r)
    v = { "sku" => "4000", "attributes" => { "attribute_pa_bags" => "g-25-steel-grit" }, "display_price" => 123 }
    assert_nil A.price(new_html("americanhawk", variants: [v, v]), r)
    assert_nil A.price(new_html("americanhawk", variants: [v.merge("display_price" => -3)]), r)
    refute A.price(html, r)["commercial_terms_verified"]
    assert_nil A.price(html, r)["observed_hardness"]
    assert_nil A.price(html.sub('"price":"123"', '"price":"125"'), r)
    assert_nil A.price(html.sub('"price":"123"', '"price":"123","sku":"4001"'), r)
  end

  def test_americanhawk_aggregate_bounds_agree_with_complete_variant_set
    r = new_source("americanhawk")
    offer = { "@type" => "AggregateOffer", "url" => r["source_url"], "priceCurrency" => "USD", "lowPrice" => "123", "highPrice" => "999", "offerCount" => 2 }
    html = new_html("americanhawk", { "offers" => [offer] })
    assert_equal "123.0", A.price(html, r)["unit_price"]
    assert_nil A.price(new_html("americanhawk", { "offers" => [offer.merge("lowPrice" => "124")] }), r)
    assert_nil A.price(new_html("americanhawk", { "offers" => [offer.merge("highPrice" => "998")] }), r)
    assert_nil A.price(new_html("americanhawk", { "offers" => [offer.merge("offerCount" => 3)] }), r)
  end

  def test_new_dealers_refresh_through_source_book_without_offers
    bodies = %w[national americanhawk].to_h { |p| [new_source(p)["source_url"], new_html(p)] }
    calls = []
    http = Object.new
    http.define_singleton_method(:get) do |url|
      calls << url
      { "ok" => true, "body" => bodies.fetch(url, ""), "retrieved_at" => Time.now.utc.iso8601 }
    end
    items = DistributorPricing::Catalog.new.items.select { |i| %w[RC-STEELGRIT-G25 RC-STEELGRIT-G40].include?(i["part_number"]) }
    book = DistributorPricing::SourceBook.new(http_client: http)
    2.times do |n|
      result = book.refresh(items: items, request: { "request_id" => "grit-#{n}" })
      result.each_value do |row|
        assert_empty row["offers"]
        assert_equal 1, row["public_market_prices"].size
        refute row["public_market_prices"].first["usable_as_delivered_benchmark"]
      end
    end
    bodies.each_key { |url| assert_equal 2, calls.count(url) }
  end
end
