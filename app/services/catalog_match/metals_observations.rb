module CatalogMatch
  # Public listings observed for sample metals rows (data/metals/price_observations.json).
  #
  # A metals row gets a benchmark price only when two independent suppliers
  # list the same spec (grade, finish, size, thickness within 2%), per the
  # admission rule in docs/data/CATALOG_PRICING.md. One listing is shown to
  # the rep as a reference but never becomes a price.
  class MetalsObservations
    PATH = Rails.root.join("data/metals/price_observations.json")
    THICKNESS_TOLERANCE = 0.02

    class << self
      attr_writer :observations

      def observations
        @observations ||= File.exist?(PATH) ? JSON.parse(File.read(PATH)) : []
      end

      def reset! = @observations = nil

      def for_item(item)
        observations.select { |observation| observation["pn"] == item["pn"] && exact_spec?(observation, item) }
      end

      def benchmark(item)
        # Provisional listings (spec not verified) are references, never price inputs.
        matches = for_item(item).reject { |observation| observation["provisional"] }
        suppliers = matches.group_by { |observation| observation["supplier"].to_s.downcase.strip }
        return nil if suppliers.size < 2

        prices = suppliers.values.map { |rows| rows.map { |row| BigDecimal(row["unit_price_usd"].to_s) }.min }.sort
        midpoint = ((prices.first + prices.last) / 2).round(2)
        as_of = matches.map { |row| row["observed_at"].to_s }.max
        {
          "unit_price" => midpoint,
          "currency" => "USD",
          "price_source" => "Midpoint of #{suppliers.size} public listings (#{suppliers.values.map { |rows| rows.first['supplier'] }.join(', ')}), observed #{as_of.first(10)}",
          "benchmark" => {
            "name" => "Public listing midpoint, #{suppliers.size} suppliers",
            "as_of" => as_of.to_s.first(10),
            "kind" => "public_listing_midpoint",
            "unit" => "USD per #{item['unit'] || 'each'}",
            "explanation" => "Listings from #{prices.first.to_s('F')} to #{prices.last.to_s('F')} USD, product only; delivery surcharges and certificates " \
                             "are extra where noted (#{matches.map { |row| row['source_url'] }.uniq.join(' ')})."
          }
        }
      end

      private

      def exact_spec?(observation, item)
        same = ->(a, b) { a.to_s.strip.casecmp?(b.to_s.strip) }
        thickness_ok = observation["thickness_in"].to_f.positive? && item["thickness_in"].to_f.positive? &&
                       (observation["thickness_in"].to_f - item["thickness_in"].to_f).abs / item["thickness_in"].to_f <= THICKNESS_TOLERANCE
        grades = Array(item["grades_satisfied"]).map { |grade| grade.to_s.upcase }
        thickness_ok &&
          (grades.include?(observation["grade"].to_s.upcase) || same.call(observation["grade"], item["grade"])) &&
          same.call(observation["finish"], item["finish"]) &&
          observation["width_in"].to_f == item["width_in"].to_f && observation["length_in"].to_f == item["length_in"].to_f
      end
    end
  end
end
