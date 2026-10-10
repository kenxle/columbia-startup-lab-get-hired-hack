# frozen_string_literal: true

require "json"
require "bigdecimal"
require "time"

# Standalone Ruby data adapter. Rails can require this file without adding gems.
# It reads data only. It does not write models or mark quotes ready.
module RfqCatalog
  class InvalidCatalog < StandardError; end

  class Reader
    attr_reader :items, :observations, :summary

    def initialize(directory)
      @directory = File.expand_path(directory.to_s)
      @items = load_json("catalog.json")
      @observations = load_json("price_observations.json")
      @sources = load_json("source_manifest.json")
      @summary = load_json("summary.json")
      @items_by_part = @items.to_h { |item| [item.fetch("part_number"), item] }
      @observations_by_id = @observations.to_h { |offer| [offer.fetch("observation_id"), offer] }
    end

    def find(part_number)
      @items_by_part[part_number.to_s.strip.upcase]
    end

    def offers_for(part_number)
      item = find(part_number)
      return [] unless item

      item.fetch("observation_ids").map { |id| @observations_by_id.fetch(id) }
    end

    def price_reference(part_number)
      item = find(part_number)
      return nil unless item

      offers = offers_for(part_number)
      prices = offers.map { |offer| decimal(offer.fetch("advertised_price_usd")) }
      {
        part_number: item.fetch("part_number"), currency: "USD", unit: "each",
        source_count: offers.length, minimum: prices.min, maximum: prices.max,
        midpoint: prices.sum / BigDecimal(prices.length.to_s),
        dimensions_verified: item.dig("specification_verification", "dimensions_verified"),
        specification_gaps: item.dig("specification_verification", "unverified_fields"),
        suggested_selling_price: nil, quote_ready: false,
        qualification: item.dig("market_reference", "qualification"),
        sources: offers.map { |offer| { supplier: offer.fetch("supplier"), url: offer.fetch("source_url"), observed_at: offer.fetch("observed_at") } }
      }
    end

    def validate!(expected_items: 500)
      check(@items.length == expected_items, "Unexpected item count")
      check(@observations.length == expected_items * 2, "Each item needs two price observations")
      check(@items_by_part.length == @items.length, "Duplicate part numbers")
      check(@items.map { |i| i.fetch("item_id") }.uniq.length == @items.length, "Duplicate item IDs")
      check(@observations_by_id.length == @observations.length, "Duplicate observation IDs")
      sources = @sources.to_h { |source| [source.fetch("id"), source] }
      referenced = []

      @items.each do |item|
        part = item.fetch("part_number")
        check(item.fetch("quote_ready") == false, "Unconfirmed item marked quote ready")
        check(item["suggested_quote_price_usd_each"].nil?, "Selling price must remain unset")
        ids = item.fetch("observation_ids")
        check(ids.length == 2 && ids.uniq.length == 2, "Missing independent price pair")
        offers = ids.map { |id| @observations_by_id.fetch(id) }
        check(offers.map { |offer| offer.fetch("supplier") }.uniq.length == 2, "Duplicate dealer")
        referenced.concat(ids)
        offers.each do |offer|
          source = sources.fetch(offer.fetch("source_id"))
          check(offer.fetch("item_id") == item.fetch("item_id"), "Wrong observation owner")
          check(offer.fetch("canonical_part_number") == part, "Wrong canonical part")
          check(sku_matches?(offer, part), "Undocumented supplier SKU substitution")
          check(offer.fetch("source_url") == source.fetch("url"), "Untraceable source URL")
          check(offer.fetch("observed_at") == source.fetch("retrieved_at"), "Untraceable observation time")
          Time.iso8601(offer.fetch("observed_at"))
          check(decimal(offer.fetch("advertised_price_usd")).positive?, "Invalid price")
          check(offer.fetch("currency") == "USD", "Wrong currency")
          check(offer.fetch("sale_unit") == "each" && offer.fetch("pack_quantity") == 1 && offer.fetch("comparison_quantity") == 1, "Pack or quantity mismatch")
          check(offer.fetch("stock_reported") == true, "No reported stock")
          check(offer.fetch("formal_quote") == false, "Public listing mislabeled as formal quote")
        end
        reference = price_reference(part)
        market = item.fetch("market_reference")
        check(reference[:minimum] == decimal(market.fetch("min_usd_each")), "Incorrect minimum")
        check(reference[:maximum] == decimal(market.fetch("max_usd_each")), "Incorrect maximum")
        check(reference[:midpoint] == decimal(market.fetch("midpoint_usd_each")), "Incorrect midpoint")
        spec = item.fetch("specification_verification")
        check(spec.fetch("readable_conflicts").empty?, "Conflicting specification admitted")
        check(spec.fetch("dimensions_verified") == spec.fetch("unverified_fields").empty?, "Specification gaps hidden")
      end
      check(referenced.sort == @observations.map { |o| o.fetch("observation_id") }.sort, "Orphan or reused observations")
      check(@summary.fetch("item_count") == @items.length && @summary.fetch("observation_count") == @observations.length, "Incorrect summary")
      true
    rescue KeyError, ArgumentError, JSON::ParserError => e
      raise InvalidCatalog, e.message
    end

    private

    def load_json(name)
      JSON.parse(File.read(File.join(@directory, name)))
    end

    def decimal(value)
      BigDecimal(value.to_s)
    end

    def check(condition, message)
      raise InvalidCatalog, message unless condition
    end

    def sku_matches?(offer, canonical)
      sku = offer.fetch("supplier_part_number")
      return true if sku == canonical

      # Explicit supplier handedness supports this mapping, not a guessed alias.
      canonical.match?(/\AAN31[56]-\d+R\z/) && sku == canonical.delete_suffix("R") &&
        offer["sku_mapping_evidence"] && offer.dig("source_specification_fields", "product type") == "Right"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  directory = ARGV.fetch(0, File.expand_path("../../data/aviation", __dir__))
  reader = RfqCatalog::Reader.new(directory)
  reader.validate!
  puts "PASS: #{reader.items.length} unique items and #{reader.observations.length} sourced real price observations; exact decimal arithmetic and specification holds validated."
end
