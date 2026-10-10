module CatalogMatch
  # The labeled, dated price reference a catalog row carries today, if any.
  #
  # - rudco rows: the list price shown on rud-co.com when the catalog was
  #   built (website list price, not a quote or a supplier offer).
  # - aviation rows: the midpoint of two public dealer listings, one piece.
  # - metals rows: none. They stay unpriced until a sourced price exists.
  #
  # Shape matches a QuoteLine: unit_price, currency, price_source, benchmark
  # {name, as_of, kind, unit, explanation}. nil means "no labeled price".
  class Benchmark
    def self.for(item)
      return nil unless item.is_a?(Hash)

      case item["catalog"]
      when "rudco" then rudco(item)
      when "aviation" then aviation(item)
      when "metals" then MetalsObservations.benchmark(item)
      end
    end

    # Listings the rep can see even when there are too few to price from.
    def self.references(item)
      item.is_a?(Hash) && item["catalog"] == "metals" ? MetalsObservations.for_item(item) : []
    end

    def self.rudco(item)
      price = item["list_price_usd_per_lb"]
      return nil unless price.is_a?(Numeric) && price.positive?

      as_of = manifest("rudco")["fetched_at"]
      source = item["list_price_source"] || {}
      {
        "unit_price" => BigDecimal(price.to_s),
        "currency" => "USD",
        "price_source" => "RudCo website list price, rud-co.com, fetched #{as_of.to_s.first(10)}",
        "benchmark" => {
          "name" => "RudCo website list price",
          "as_of" => as_of,
          "kind" => "website_list_price",
          "unit" => "USD per lb",
          "explanation" => "The $/lb shown on rud-co.com for #{item['grade']} (#{source['url']}). A list price, not a quote: " \
                           "order quantity, freight and certificates are not included."
        }
      }
    end

    def self.aviation(item)
      reference = item["market_reference"] || {}
      midpoint = reference["midpoint_usd_each"]
      return nil unless midpoint.is_a?(Numeric) && midpoint.positive? && reference["source_count"].to_i >= 2

      as_of = manifest("aviation")["created_at"]
      {
        "unit_price" => BigDecimal(midpoint.to_s),
        "currency" => "USD",
        "price_source" => "Midpoint of #{reference['source_count']} public dealer listings, observed #{as_of.to_s.first(10)}",
        "benchmark" => {
          "name" => "Two-dealer public listing midpoint",
          "as_of" => as_of,
          "kind" => "dealer_listing_midpoint",
          "unit" => "USD each",
          "explanation" => "Listings from #{reference['min_usd_each']} to #{reference['max_usd_each']} USD each, one piece, " \
                           "product only (#{reference['interpretation']})."
        }
      }
    end

    def self.manifest(name)
      @manifest ||= {}
      @manifest[name] ||= begin
        path = Rails.root.join("data/#{name}/#{name == 'rudco' ? 'source_manifest' : 'summary'}.json")
        File.exist?(path) ? JSON.parse(File.read(path)) : {}
      end
    end

    def self.reset! = @manifest = nil
  end
end
