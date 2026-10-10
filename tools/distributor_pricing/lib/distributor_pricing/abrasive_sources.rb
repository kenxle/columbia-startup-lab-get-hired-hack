# frozen_string_literal: true

require_relative "additional_sources"

module DistributorPricing
  # Routes contain identities only. Every amount comes from this run's HTML.
  module AbrasiveSources
    HOSTS = %w[kleenblast.com catalog.precisionfinishinginc.com www.ntruddock.com].freeze
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
      case route["parser"]
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
        "limitations" => "Product-only 50 lb bag reference. Hardness, composition, certification, allocation, quantity terms, freight, tax and delivery require confirmation. Published tiers are observations, not executable offers. Ton columns are excluded because their price basis is unverified." }
    end

    def self.tier(min, max, amount)
      value = AdditionalSources.positive(amount)
      { "min" => min, "max" => max, "unit_price" => value } if value
    end
  end
end
