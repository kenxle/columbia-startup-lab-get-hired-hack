# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/distributor_pricing/source_book"
require_relative "../lib/distributor_pricing/catalog"
require_relative "../lib/distributor_pricing/gateway_client"
require_relative "../lib/distributor_pricing/supplier_feed"

class DistributorSourcesTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  NOW = Time.utc(2026, 10, 10, 18)

  class PublicHTTP
    attr_accessor :price, :bad_unit
    attr_reader :calls
    def initialize(rows)
      @rows, @price, @calls = rows, "1.11", []
    end
    def get(url)
      @calls << url
      rows = @rows.select { |row| row["source_url"] == url }
      body = if url.include?("aircraftspruce.com")
        products = rows.to_h do |row|
          values = Array.new(28)
          values[1], values[2], values[27] = "Synthetic bolt", @price, @bad_unit ? "Box" : "Each"
          [row["supplier_part_number"], values]
        end
        "var products = #{JSON.generate(products)};\nvar stock = {};"
      elsif url.include?("wicksaircraft.com")
        rows.map do |row|
          "<tr><span itemprop=\"sku\">#{row['supplier_part_number']}</span><td class=\"list-price\">$#{@price}</td><meta itemprop=\"lowPrice\" content=\"#{@price}\"><a data-field-name=\"sold by\" data-field-value=\"#{@bad_unit ? 'Box' : 'Each'}\"></a>Qty in Stock: 10</tr>"
        end.join
      else
        "No confirmed exact SKU price here"
      end
      { "ok" => true, "body" => body, "retrieved_at" => NOW.iso8601, "url" => url }
    end
  end

  def setup
    @catalog = DistributorPricing::Catalog.new(root: ROOT)
    @rows = JSON.parse(File.read(File.join(ROOT, "data/aviation/price_observations.json")))
    @http = PublicHTTP.new(@rows)
    @book = DistributorPricing::SourceBook.new(root: ROOT, http_client: @http)
    @item = @catalog.find("AN3-13A")
  end

  def refresh
    @book.refresh(items: [@item, @item], request: { "request_id" => "test-current-run" }).fetch("AN3-13A")
  end

  def test_saved_prices_never_supply_the_next_quote_and_five_competitors_are_checked
    first = refresh
    assert_equal 2, first["public_market_prices"].size
    assert_equal %w[1.11], first["public_market_prices"].map { |row| row["unit_price"] }.uniq
    assert_equal 5, first["source_checks"].map { |row| row["supplier"] }.uniq.size
    assert_equal @http.calls.uniq.size, @http.calls.size
    @http.price = "2.22"
    second = refresh
    assert_equal %w[2.22], second["public_market_prices"].map { |row| row["unit_price"] }.uniq
    assert_equal 2, @http.calls.count { |url| url == @rows.find { |row| row["canonical_part_number"] == "AN3-13A" }["source_url"] }
    refute first["offers"].any? { |offer| offer["commercial_terms_verified"] || offer["stock_confirmed"] }
    refute first["public_market_prices"].any? { |price| price["usable_as_delivered_benchmark"] }
  end

  def test_sale_unit_change_does_not_reuse_the_previous_each_price
    refresh
    @http.bad_unit = true
    result = refresh
    assert_empty result["offers"]
    assert_empty result["public_market_prices"]
    assert_equal 2, result["source_checks"].count { |check| check["ok"] == false }
  end

  def test_airfasco_moq_and_pack_are_preserved_and_wrong_part_rejected
    route = DistributorPricing::AdditionalSources.routes(@item).first
    body = "<table>Part Number AN3-13A Stock 128 Unit of Measure EA Packaged Amount 10 PER Retail Price Min Order QTY 10 Price $ 0.4000 / EA</table>"
    price = DistributorPricing::AdditionalSources.price(body, route)
    assert_equal "0.4", price["unit_price"]
    assert_equal "10", price["minimum_quantity"]
    assert_equal "10", price["pack_size"]
    assert_nil DistributorPricing::AdditionalSources.price(body.sub("AN3-13A", "AN3-13"), route)
  end

  def test_monroe_unknown_pack_and_unit_stay_unknown
    route = DistributorPricing::AdditionalSources.routes(@item).last
    data = { "product_attributes" => { "sku" => "AN3-13A", "price" => { "without_tax" => { "value" => "0.38", "currency" => "USD" } } } }
    price = DistributorPricing::AdditionalSources.price("var BCData = #{JSON.generate(data)};", route)
    assert_equal "0.38", price["unit_price"]
    assert_nil price["unit"]
    assert_nil price["pack_size"]
    data["product_attributes"]["sku"] = "AN3-13"
    assert_nil DistributorPricing::AdditionalSources.price("var BCData = #{JSON.generate(data)};", route)
  end

  def test_pegasus_tier_evidence_keeps_exact_part_and_individual_basis
    route = DistributorPricing::AdditionalSources.routes(@item)[1]
    body = 'Sold individually <tr><p>AN3-13A<br><span itemprop="sku">31107</span></p><meta itemprop="priceCurrency" content="USD">1 to 11: $0.49 12 &amp; up: $0.45</tr>'
    price = DistributorPricing::AdditionalSources.price(body, route)
    assert_equal "0.49", price["unit_price"]
    assert_equal "11", price["published_tiers"].first["max"]
    assert_nil price["published_tiers"].last["max"]
    assert_nil DistributorPricing::AdditionalSources.price(body.sub("Sold individually", "Sold in boxes"), route)
    assert_nil DistributorPricing::AdditionalSources.price(body.sub("AN3-13A<br", "AN3-13<br"), route)
  end
end

class DistributorGatewayAndFeedTest < Minitest::Test
  NOW = Time.utc(2026, 10, 10, 18)
  class HTTP
    attr_reader :requests
    attr_accessor :content
    def initialize(content)
      @content, @requests = content, []
    end
    def post_json(url, payload, token:)
      @requests << payload
      { "ok" => true, "retrieved_at" => NOW.iso8601, "body" => JSON.generate("choices" => [{ "message" => { "content" => @content } }]) }
    end
    def get(url)
      @requests << URI(url)
      { "ok" => true, "body" => JSON.generate(@content), "retrieved_at" => NOW.iso8601 }
    end
  end

  def test_model_cannot_return_prices_or_nonverbatim_items
    text = "AN3-13A qty 1 ea"
    http = HTTP.new(JSON.generate("lines" => [{ "original_text" => text, "quantity" => "1", "unit" => "each", "unit_price" => "0.01", "stock" => "10000" }]))
    gateway = DistributorPricing::GatewayClient.new(token: "SYNTHETIC-TEST-TOKEN", http_client: http)
    result = gateway.extract(text)
    assert result["ok"]
    refute result["lines"].first.key?("unit_price")
    refute result["lines"].first.key?("stock")
    http.content = JSON.generate("lines" => [{ "original_text" => "AN3-5A qty 1 ea" }])
    refute gateway.extract(text)["ok"]
    http.content = "not JSON"
    refute gateway.extract(text)["ok"]
  end

  def test_feed_requires_same_run_nonce_and_current_check_time
    request = { "request_id" => "fresh-run", "started_at" => NOW.iso8601, "items" => [], "rfq_text" => "PRIVATE RFQ MUST NOT BE SENT" }
    http = HTTP.new("request_id" => "fresh-run", "checked_at" => NOW.iso8601, "lines" => {})
    feed = DistributorPricing::SupplierFeed.new(endpoint: "https://supplier.example/quotes", http_client: http, clock: -> { NOW })
    assert feed.refresh(request: request)["ok"]
    sent = URI.decode_www_form(http.requests.first.query).to_h
    refute sent["request"].include?("PRIVATE RFQ")
    http.content["request_id"] = "old-run"
    refute feed.refresh(request: request)["ok"]
    http.content["request_id"] = "fresh-run"
    http.content["checked_at"] = (NOW - 1).iso8601
    refute feed.refresh(request: request)["ok"]
    http.content["checked_at"] = (NOW + 1).iso8601
    refute feed.refresh(request: request)["ok"]
  end

  def test_llm_gateway_cannot_be_configured_as_supplier_feed
    assert_raises(ArgumentError) { DistributorPricing::SupplierFeed.new(endpoint: "https://api.nicrron.ai/v1/chat/completions") }
    assert_raises(ArgumentError) { DistributorPricing::SupplierFeed.new(endpoint: "http://supplier.example/quotes") }
  end
end
