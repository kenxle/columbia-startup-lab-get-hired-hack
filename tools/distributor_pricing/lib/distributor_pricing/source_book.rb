# frozen_string_literal: true

require "json"
require "cgi"
require "bigdecimal"
require "time"
require_relative "http_client"
require_relative "additional_sources"

module DistributorPricing
  # Saved records identify real sources; they never supply current quote prices.
  # Each refresh creates its own request-local page cache and does real GETs.
  class SourceBook
    def initialize(root: File.expand_path("../../../..", __dir__), http_client: nil, clock: -> { Time.now.utc })
      @root, @clock = root, clock
      @observations = JSON.parse(File.read(File.join(root, "data/aviation/price_observations.json")))
      @directory = JSON.parse(File.read(File.join(root, "data/distributor_pricing/supplier_directory.json")))
      hosts = HttpClient::DEFAULT_HOSTS + AdditionalSources::HOSTS + @directory.map { |r| URI(r.fetch("source_url")).hostname }
      @http = http_client || HttpClient.new(allowed_hosts: hosts.uniq)
    end

    def refresh(items:, request:)
      unique_items = items.compact.uniq { |item| item.fetch("part_number") }
      urls = unique_items.flat_map do |item|
        if item["source_catalog"] == "aviation"
          observation_rows(item).map { |row| row.fetch("source_url") } + AdditionalSources.routes(item).map { |route| route.fetch("source_url") }
        else
          matching_routes(item).map { |route| route.fetch("source_url") }
        end
      end
      pages = fetch_pages(urls.uniq) # This quote only, never reused next run.
      unique_items.to_h do |item|
        offers, checks, routes, extra_prices = [], [], [], []
        if item["source_catalog"] == "aviation"
          rows = observation_rows(item)
          rows.each do |row|
            url = row.fetch("source_url")
            response = pages.fetch(url)
            check = response.reject { |key, _| key == "body" }.merge("supplier" => row["supplier"], "part_number" => item["part_number"])
            checks << check
            routes << row.slice("supplier", "source_url").merge("quote_url" => url, "buy_url" => url, "role" => "dealer")
            next unless response["ok"]

            live = live_listing(response.fetch("body"), row)
            unless live
              check.merge!("ok" => false, "error" => { "code" => "unverified_listing", "message" => "Current exact-SKU price/unit/stock fields could not be verified." })
              next
            end
            offers << {
              "id" => "#{request['request_id']}-#{row['observation_id']}", "supplier" => row["supplier"],
              "part_number" => item["part_number"], "supplier_sku" => row["supplier_part_number"],
              "source_url" => url, "quote_url" => url, "buy_url" => url,
              "retrieved_at" => response.fetch("retrieved_at"), "currency" => "USD", "unit" => "each",
              "unit_price" => live.fetch("price"), "pack_size" => "1", "minimum_quantity" => "1",
              "tier" => { "min" => "1", "max" => "1" },
              "stock_quantity" => live["stock_quantity"], "stock_confirmed" => false,
              "stock_listing_claim" => live["stock_claim"], "commercial_terms_verified" => false,
              "commercial_evidence" => "Fresh public listing, not an executable supplier quote or checkout confirmation.",
              "condition" => "new", "specs" => {}, "certifications" => [], "origin" => nil,
              "lead_time_days" => nil, "destination" => nil, "costs" => {}, "payment_fee" => nil,
              "order_conditions" => { "line_sufficient" => false, "evidence" => nil },
              "evidence_kind" => "live_public_product_listing", "request_id" => request["request_id"],
              "unknown_terms" => ["requested quantity tier", "confirmed stock allocation", "certificates and origin", "freight", "lead time", "supplier order conditions", "nonrecoverable tax", "payment and financing costs"]
            }
          end
          AdditionalSources.routes(item).each do |route|
            response = pages.fetch(route.fetch("source_url"))
            check = response.reject { |key, _| key == "body" }.merge("supplier" => route["supplier"], "part_number" => item["part_number"])
            checks << check
            routes << route.reject { |key, _| key == "parser" }.merge("checked_at" => response["retrieved_at"], "live_page_available" => response["ok"])
            live = response["ok"] && AdditionalSources.price(response.fetch("body"), route)
            check["listing_status"] = live ? "exact_sku_price_observed" : "price_or_specification_not_verified"
            next unless live
            extra_prices << live.merge("supplier" => route["supplier"], "part_number" => item["part_number"], "source_url" => route["source_url"],
                                       "retrieved_at" => response["retrieved_at"], "price_scope" => "product_only_published_basis",
                                       "usable_as_delivered_benchmark" => false, "request_id" => request["request_id"])
          end
        else
          matching_routes(item).each do |route|
            response = pages.fetch(route.fetch("source_url"))
            checks << response.reject { |key, _| key == "body" }.merge("supplier" => route["supplier"], "purpose" => "live_supplier_quote_route")
            routes << route.merge("checked_at" => response["retrieved_at"], "live_page_available" => response["ok"])
          end
        end
        [item.fetch("part_number"), { "offers" => offers, "public_market_prices" => offers.map { |o| public_reference(o) } + extra_prices,
                                      "supplier_routes" => routes, "source_checks" => checks,
                                      "refreshed_for_request_id" => request["request_id"] }]
      end
    end

    private

    def observation_rows(item)
      @observations.select { |row| row["canonical_part_number"] == item["part_number"] || row["supplier_part_number"] == item["part_number"] }
    end

    # Four bounded workers keep slow independent competitors from serializing
    # every RFQ. Each URL is fetched once per run, with no persistent cache.
    def fetch_pages(urls)
      queue = Queue.new
      urls.each { |url| queue << url }
      results, lock = {}, Mutex.new
      workers = Array.new([4, urls.size].min) do
        Thread.new do
          loop do
            url = queue.pop(true) rescue nil
            break unless url
            begin
              result = @http.get(url)
            rescue StandardError => error
              result = { "ok" => false, "url" => url, "retrieved_at" => @clock.call.utc.iso8601,
                         "error" => { "code" => "source_failure", "message" => "Source retrieval failed (#{error.class})." } }
            end
            lock.synchronize { results[url] = result }
          end
        end
      end
      workers.each(&:join)
      results
    end

    def public_reference(offer)
      offer.slice("supplier", "part_number", "supplier_sku", "unit", "currency", "unit_price", "retrieved_at", "source_url").merge(
        "price_scope" => "product_only_single_piece", "usable_as_delivered_benchmark" => false,
        "reason" => "Requested quantity, destination, required charges, certification and delivery terms are not confirmed.")
    end

    def matching_routes(item)
      @directory.select do |route|
        material = item["material"].to_s.downcase
        route.fetch("materials").any? { |name| material.include?(name.downcase) || (name == "aluminum" && material.include?("aluminium")) } &&
          (!route["grades"] || route["grades"].include?(item["grade"])) &&
          (!route["forms"] || route["forms"].include?(item["form"]))
      end
    end

    def live_listing(html, row)
      sku = row.fetch("supplier_part_number")
      if row["supplier"] == "Aircraft Spruce"
        products = JSON.parse(html.match(/var products = (\{[^\n]*\});/)&.[](1) || "{}")
        stock = JSON.parse(html.match(/var stock = (\{[^\n]*\});/)&.[](1) || "{}")
        p = products[sku]
        return nil unless p.is_a?(Array) && %w[Each Piece].include?(p[27]) && !p[1].to_s.match?(/pack|box/i)
        price = positive(p[2])
        return nil unless price
        quantities = (stock[sku] || {}).values.select { |v| v.is_a?(Hash) && v.key?("avail") }.map { |v| v["avail"].to_i }
        { "price" => price, "stock_quantity" => quantities.max, "stock_claim" => "Public warehouse listing; allocation and delivery not committed" }
      else
        tr = html.scan(/<tr\b[^>]*>[\s\S]*?<\/tr>/i).find { |r| r.include?("<span itemprop=\"sku\">#{sku}</span>") }
        return nil unless tr
        price = positive(tr.match(/<td class="list-price">[\s\S]*?\$([\d.]+)/)&.[](1))
        embedded = positive(tr.match(/itemprop="lowPrice" content="([\d.]+)"/)&.[](1))
        return nil unless price && price == embedded
        sold = tr.match(/data-field-name="sold by"\s+data-field-value="([^"]*)"/)&.[](1)
        return nil unless sold == "Each"
        claim = CGI.unescapeHTML(tr.gsub(/<[^>]*>/, " ")).match(/Qty in Stock:\s*(\d+)|Out of Stock/)&.[](0)
        qty = claim&.match(/Qty in Stock:\s*(\d+)/)&.[](1)
        { "price" => price, "stock_quantity" => qty&.to_i || 0, "stock_claim" => claim || "unconfirmed" }
      end
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end

    def positive(value)
      number = BigDecimal(value.to_s)
      number.to_s("F") if number.finite? && number.positive?
    rescue ArgumentError
      nil
    end
  end
end
