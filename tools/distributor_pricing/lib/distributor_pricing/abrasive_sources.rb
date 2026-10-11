# frozen_string_literal: true

require_relative "additional_sources"

module DistributorPricing
  # Routes contain identities only. Every amount comes from this run's HTML.
  module AbrasiveSources
    HOSTS = %w[kleenblast.com catalog.precisionfinishinginc.com www.ntruddock.com nationalblastsupply.com americanhawkindustrialproducts.com].freeze
    MAX_HTML_BYTES = 3_000_000

    def self.routes(item)
      size = item["grade"].to_s.upcase.delete("- ")
      return [] unless %w[S330 S170 G40 G25].include?(size) && item["material"].to_s.match?(/\Asteel (?:shot|grit)\z/i)
      shot = size.start_with?("S")
      return [] unless item["material"].downcase == (shot ? "steel shot" : "steel grit")
      sku = "#{shot ? 'SS' : 'SG'}50#{size[1..]}"
      kleen = size == "G25" ? "https://kleenblast.com/viewitems/specialty-abrasives-blast-media/steel-grit" : "https://kleenblast.com/item/specialty-abrasives-blast-media/steel-#{shot ? 'shot' : 'grit'}/#{sku.downcase}"
      rows = [["Kleen Blast", kleen, sku, "kleen"],
              ["N.T. Ruddock", "https://www.ntruddock.com/product/steel-#{shot ? 'shot' : 'grit'}-blasting-media/", shot ? "ABR-011" : "ABR-010", "ruddock"]]
      rows << ["Precision Finishing", "https://catalog.precisionfinishinginc.com/item/metallic-abrasives/steel-shot/item-#{size == 'S330' ? '4231' : '4233'}", "SS-#{size[1..]}", "precision"] if shot
      rows << ["National Blast Supply", "https://nationalblastsupply.com/products/nbs-steel-grit-50-lb-bag-g40-medium", "NBS-SG40-50", "national"] if size == "G40"
      rows << ["AmericanHawk Industrial Products", "https://americanhawkindustrialproducts.com/product/steel-grit/", "4000", "americanhawk"] if size == "G25"
      rows.map { |supplier, url, code, parser| { "supplier" => supplier, "source_url" => url, "quote_url" => url, "supplier_sku" => code, "size" => size, "parser" => parser, "role" => "dealer" } }
    end

    def self.price(html, route)
      # HTTP bodies arrive as bytes. Accept valid UTF-8 without altering those
      # bytes; never scrub or guess a legacy encoding around prices or sizes.
      return nil unless html.is_a?(String) && html.bytesize <= MAX_HTML_BYTES
      html = html.dup.force_encoding(Encoding::UTF_8)
      return nil unless html.valid_encoding?

      # CGI.unescapeHTML leaves &nbsp; as text; dealer tier tables use it between words.
      html = html.gsub(/&nbsp;|&#160;|&#xa0;/i, " ")
      text = AdditionalSources.plain(html).tr("\u00a0", " ").gsub(/\s+/, " ")
      size, sku = route.values_at("size", "supplier_sku")
      tiers = []
      hardness = nil
      case route["parser"]
      when "national"
        product = structured_product(html, route["source_url"])
        return nil unless product && product["sku"] == sku && product["name"].to_s.match?(/\bG40\b/) && product["name"].to_s.match?(/\b50\s*lb\s+Bag\b/i)
        offer = product["offers"]
        return nil unless offer.is_a?(Hash) && offer["@type"] == "Offer" && offer["priceCurrency"] == "USD" && offer["url"] == route["source_url"]
        amount = offer["price"]
        hardness = text.match(/\bHardness\s+(\d+\s*[-–]\s*\d+\s*HRC)\b/i)&.[](1)
      when "americanhawk"
        product = structured_product(html, route["source_url"])
        return nil unless product && product["description"].to_s.match?(/\b50\s*lbs?\s+Bag\b/i) && product["description"].to_s.match?(/Part:\s*4000\s*\(25 Steel Grit\)/i)
        offers = product["offers"]
        return nil unless offers.is_a?(Array) && !offers.empty? && offers.all? { |o| o.is_a?(Hash) && o["priceCurrency"] == "USD" && o["url"] == route["source_url"] }
        form = html.scan(/<form\b[^>]*>/i).find { |tag| tag.match?(/\baction=["']#{Regexp.escape(route['source_url'])}["']/i) && tag.include?("data-product_variations=") }
        return nil unless form
        encoded = form.match(/\bdata-product_variations=(["'])(.*?)\1/m)&.[](2)
        variants = JSON.parse(CGI.unescapeHTML(encoded.to_s))
        return nil unless variants.is_a?(Array)
        matches = variants.select { |v| v.is_a?(Hash) && v["sku"] == sku && v["attributes"] == { "attribute_pa_bags" => "g-25-steel-grit" } }
        return nil unless matches.size == 1
        amount = matches.first["display_price"]
        return nil unless american_offer_agrees?(offers, variants, matches.first)
      when "kleen"
        if route["source_url"].include?("/viewitems/")
          row = html.scan(/<tr\b[^>]*>[\s\S]*?<\/tr>/i).find { |r| AdditionalSources.plain(r).match?(/\b#{Regexp.escape(sku)}\b/) }
          return nil unless row
          text = AdditionalSources.plain(row)
        else
          title = AdditionalSources.plain(html[/<h1\b[^>]*>[\s\S]*?<\/h1>/i].to_s)
          return nil unless title.match?(/\b#{Regexp.escape(sku)}\b/) && title.match?(/\b#{size}\b/)
        end
        return nil unless text.match?(/\b#{size}\s+50\s*lb\.?\s+Bag\b/i)
        amount = if route["source_url"].include?("/viewitems/")
          text.match(/\$\s*(\d+(?:\.\d+)?)/)&.[](1)
        else
          text.match(/\bPrice\s*\$\s*(\d+(?:\.\d+)?)/)&.[](1)
        end
      when "precision"
        title = AdditionalSources.plain(html[/<h1\b[^>]*>[\s\S]*?<\/h1>/i].to_s)
        return nil unless title.match?(/\b#{Regexp.escape(sku)}\b/) && text.match?(/Packaging\s+(?:N\/A\s+)?50\s*lb\.?\s+bag/i)
        amount = text.match(/List Price\s*\$\s*(\d+(?:\.\d+)?)/)&.[](1)
        tiers = text.scan(/(\d+)\s*(?:-\s*(\d+)|and\s+up)\s*\$\s*(\d+(?:\.\d+)?)/i).map { |min, max, price| tier(min, max, price) }.compact.uniq
      when "ruddock"
        return nil unless text.match?(/SKU:\s*#{Regexp.escape(sku)}\b/) && text.match?(/packaged in 50\s*lb\.?\s+bags/i)
        html.scan(/<table\b[^>]*>[\s\S]*?<\/table>/i).each do |table|
          rows = table.scan(/<tr\b[^>]*>[\s\S]*?<\/tr>/i).map { |r| r.scan(/<t[dh]\b[^>]*>([\s\S]*?)<\/t[dh]>/i).flatten.map { |c| AdditionalSources.plain(c).strip } }
          header = rows.find { |r| r.any? { |c| c.match?(/\A\d+\s*-\s*\d+\s+BAGS\z/i) } }
          row = rows.find { |r| r.first.to_s.match?(/\A#{size[0]}-?#{size[1..]}\z/i) }
          next unless header && row
          tiers = header.each_with_index.filter_map do |cell, i|
            range = cell.match(/\A(\d+)\s*-\s*(\d+)\s+BAGS\z/i)
            value = row[i].to_s.match(/\A\$\s*(\d+(?:\.\d+)?)(?:\s*\/BG)?\z/i)
            tier(range[1], range[2], value[1]) if range && value
          end
          break unless tiers.empty?
        end
        return nil if tiers.empty?
        amount = tiers.first["unit_price"]
      end
      amount = AdditionalSources.positive(amount)
      return nil unless amount
      { "supplier_sku" => sku, "size" => size, "unit_price" => amount, "unit" => "bag", "currency" => "USD",
        "pack_size" => "50", "pack_unit" => "lb", "published_tiers" => tiers, "tier_unit" => "bag",
        "normalized_unit" => "lb", "normalized_unit_price" => (BigDecimal(amount) / 50).to_s("F"),
        "commercial_terms_verified" => false, "stock_confirmed" => false,
        "observed_hardness" => hardness,
        "limitations" => "Product-only 50 lb bag reference. Hardness, composition, certification, allocation, quantity terms, freight, tax and delivery require confirmation. Published tiers are observations, not executable offers. Ton columns are excluded because their price basis is unverified." }
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end

    def self.structured_product(html, url)
      products = html.scan(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/i).flat_map do |body|
        data = JSON.parse(body.first)
        nodes = data.is_a?(Array) ? data : [data]
        nodes.flat_map { |node| node.is_a?(Hash) && node["@graph"].is_a?(Array) ? node["@graph"] : [node] }
      end.select { |node| node.is_a?(Hash) && node["@type"] == "Product" && node["url"] == url }
      products.one? ? products.first : nil
    end

    def self.american_offer_agrees?(offers, variants, selected)
      price = AdditionalSources.positive(selected["display_price"])
      return false unless price
      offers.any? do |offer|
        next false if offer.key?("sku") && offer["sku"].to_s != selected["sku"].to_s
        next false if offer.key?("variation_id") && offer["variation_id"].to_s != selected["variation_id"].to_s
        if offer["@type"] == "Offer"
          AdditionalSources.positive(offer["price"]) == price
        elsif offer["@type"] == "AggregateOffer"
          # This publisher supplies bounds for all variants, not individual
          # schema offers. Reconcile the entire set instead of assigning its
          # lowPrice to whichever size the buyer requested.
          amounts = variants.map { |v| v.is_a?(Hash) && AdditionalSources.positive(v["display_price"]) }
          next false unless amounts.all? && !amounts.empty? && offer["offerCount"].to_s == variants.size.to_s
          low, high = amounts.map { |p| BigDecimal(p) }.minmax.map { |p| p.to_s("F") }
          AdditionalSources.positive(offer["lowPrice"]) == low && AdditionalSources.positive(offer["highPrice"]) == high
        else
          false
        end
      end
    end

    def self.tier(min, max, amount)
      value = AdditionalSources.positive(amount)
      { "min" => min, "max" => max, "unit_price" => value } if value
    end
  end
end
