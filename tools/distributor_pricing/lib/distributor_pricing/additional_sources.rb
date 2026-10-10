# frozen_string_literal: true

require "json"
require "cgi"
require "bigdecimal"

module DistributorPricing
  # These public sources widen research to five competitors per hardware item.
  # Search routes do not establish that a SKU is sold, stocked or deliverable.
  module AdditionalSources
    HOSTS = %w[airfasco.com www.pegasusautoracing.com monroeaerospace.com].freeze

    def self.routes(item)
      part = item.fetch("part_number")
      encoded = URI.encode_www_form_component(part)
      bolt = part.match(/\A(AN[3-9]|AN1\d|AN20)(?:H)?-/)
      pegasus = bolt ? "https://www.pegasusautoracing.com/productselection.asp?Product=#{bolt[1]}" : "https://www.pegasusautoracing.com/search.asp?Search=#{encoded}"
      monroe = bolt ? "https://monroeaerospace.com/an-bolts/#{part.downcase}/" : "https://monroeaerospace.com/search.php?search_query=#{encoded}"
      [
        { "supplier" => "Airfasco", "role" => "manufacturer", "parser" => "airfasco", "source_url" => "https://airfasco.com/search/products_search.php?PartNumber=#{encoded}" },
        { "supplier" => "Pegasus Auto Racing Supplies", "role" => "dealer", "parser" => "pegasus", "source_url" => pegasus },
        { "supplier" => "Monroe Aerospace", "role" => "dealer", "parser" => "monroe", "source_url" => monroe }
      ].map { |route| route.merge("quote_url" => route["source_url"], "buy_url" => route["source_url"], "part_number" => part, "price_status" => "verify_exact_listing_or_request_quote") }
    end

    def self.price(html, route)
      part = route.fetch("part_number")
      case route.fetch("parser")
      when "airfasco"
        text = plain(html)
        return nil unless text.match?(/Part Number\s+#{Regexp.escape(part)}(?:\s|$)/i)
        price = text.match(/Retail Price\s+Min Order QTY\s+(\d+)\s+Price\s*\$\s*([\d.]+)\s*\/\s*EA/i)
        pack = text.match(/Packaged Amount\s+(\d+)\s+PER/i)
        return nil unless price && pack && price[1].to_i.positive? && pack[1].to_i.positive?
        amount = positive(price[2])
        amount && { "unit_price" => amount, "unit" => "each", "currency" => "USD", "minimum_quantity" => price[1], "pack_size" => pack[1],
                    "stock_listing_claim" => text.match(/Stock\s+(\d+)/)&.[](1), "tier" => nil,
                    "limitations" => "Retail EA price with published MOQ/pack. Tier validity, allocation and delivered terms require a quote. Drawings are labeled educational by the publisher." }
      when "pegasus"
        return nil unless plain(html).match?(/Sold individually/i)
        row = html.scan(/<tr\b[^>]*>[\s\S]*?<\/tr>/i).find { |entry| entry.match?(/<p>\s*#{Regexp.escape(part)}\s*<br/i) }
        return nil unless row
        text = plain(row)
        tiers = text.scan(/(\d+)\s+(?:to\s+(\d+)|&\s*up):\s*\$\s*([\d.]+)/i).filter_map do |min, max, value|
          amount = positive(value)
          { "min" => min, "max" => max, "unit_price" => amount } if amount
        end
        return nil if tiers.empty? || !row.match?(/itemprop="priceCurrency" content="USD"/)
        { "unit_price" => tiers.first["unit_price"], "unit" => "each", "currency" => "USD", "pack_size" => "1", "minimum_quantity" => tiers.first["min"], "published_tiers" => tiers,
          "supplier_sku" => row.match(/itemprop="sku">([^<]+)</)&.[](1), "stock_listing_claim" => text.include?("Not In Stock") ? "Not In Stock" : text.include?("In Stock") ? "In Stock" : "unknown",
          "limitations" => "Published product-only quantity tiers. Stock quantity, certificates, freight and delivery remain unconfirmed." }
      when "monroe"
        data = html.match(/var BCData = (\{[^\n]+\});/)&.[](1)
        product = data && JSON.parse(data)["product_attributes"]
        return nil unless product.is_a?(Hash) && product["sku"] == part
        amount = positive(product.dig("price", "without_tax", "value"))
        return nil unless amount && product.dig("price", "without_tax", "currency") == "USD"
        { "unit_price" => amount, "unit" => nil, "currency" => "USD", "pack_size" => nil, "minimum_quantity" => nil,
          "stock_listing_claim" => product["stock"], "limitations" => "Exact SKU product price excluding tax. Sale unit, pack, MOQ, stock quantity and delivered terms require confirmation." }
      end
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end

    def self.plain(html)
      CGI.unescapeHTML(html.gsub(/<script\b[^>]*>[\s\S]*?<\/script>/i, " ").gsub(/<[^>]*>/, " ")).gsub(/\s+/, " ")
    end

    def self.positive(value)
      number = BigDecimal(value.to_s)
      number.to_s("F") if number.finite? && number.positive?
    rescue ArgumentError
      nil
    end
  end
end
