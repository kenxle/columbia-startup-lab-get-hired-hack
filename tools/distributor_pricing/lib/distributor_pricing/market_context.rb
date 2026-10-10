# frozen_string_literal: true

require "csv"
require "date"
require "bigdecimal"
require "time"
require_relative "http_client"

module DistributorPricing
  class MarketContext
    SERIES = {
      "WPU1017" => { "name" => "Steel Mill Products", "material" => "steel" },
      "WPU102501" => { "name" => "Aluminum Mill Shapes", "material" => "aluminum" }
    }.freeze

    def initialize(http_client: HttpClient.new, clock: -> { Time.now.utc }, max_age_days: 100)
      @http_client, @clock, @max_age_days = http_client, clock, Integer(max_age_days)
      raise ArgumentError, "max_age_days must be positive" unless @max_age_days.positive?
    end

    # Every invocation requests both series. Nothing is retained for a later quote.
    def refresh
      series = SERIES.to_h { |id, definition| [id, refresh_series(id, definition, @clock.call.utc)] }
      { "refreshed_at" => @clock.call.utc.iso8601, "series" => series }
    end

    # A snapshot is scoped to the caller's current RFQ run, not a persisted cache.
    def for_item(item, snapshot: nil)
      specs = item.is_a?(Hash) && item["specs"].is_a?(Hash) ? item["specs"] : {}
      material = (item.is_a?(Hash) && (specs["material"] || item["material"])).to_s
      ids = []
      ids << "WPU1017" if material.match?(/\bsteel\b/i)
      ids << "WPU102501" if material.match?(/\balumin(?:um|ium)\b/i)
      if ids.size != 1
        return { "status" => "unavailable", "material" => material, "source" => nil,
                 "error" => { "code" => "context_unavailable", "message" => "No single relevant supported published material index was identified." },
                 "is_finished_item_price" => false, "is_acquisition_cost" => false }
      end
      current = snapshot || refresh
      context = current.is_a?(Hash) && current["series"].is_a?(Hash) && current["series"][ids.first]
      return context.merge("material" => material) if context.is_a?(Hash)

      { "status" => "unavailable", "series_id" => ids.first, "material" => material,
        "error" => { "code" => "missing_refresh", "message" => "The current quote run has no refreshed material series." },
        "is_finished_item_price" => false, "is_acquisition_cost" => false }
    end

    private

    def refresh_series(id, definition, now)
      url = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=#{id}"
      result = { "source" => "U.S. Bureau of Labor Statistics via FRED, Federal Reserve Bank of St. Louis",
                 "source_url" => "https://fred.stlouisfed.org/series/#{id}", "data_url" => url,
                 "series_id" => id, "series_name" => definition["name"], "material" => definition["material"],
                 "units" => "Index 1982=100", "frequency" => "monthly", "seasonal_adjustment" => "not seasonally adjusted",
                 "refreshed_at" => now.iso8601, "observation_date" => nil, "value" => nil,
                 "prior_observation_date" => nil, "prior_value" => nil, "change_pct" => nil,
                 "is_finished_item_price" => false, "is_acquisition_cost" => false,
                 "scope" => "Broad material producer-price context only; no SKU price, dollar conversion or acquisition-cost inference.",
                 "max_observation_age_days" => @max_age_days }
      response = @http_client.respond_to?(:get) ? @http_client.get(url) : @http_client.call(url)
      now = @clock.call.utc
      result["refreshed_at"] = now.iso8601
      unless response.is_a?(Hash) && response["ok"] == true
        return result.merge("status" => "unavailable", "error" => response.is_a?(Hash) ? response["error"] : { "code" => "fetch_failed", "message" => "Market source retrieval failed." })
      end
      rows = CSV.parse(response.fetch("body").to_s, headers: true)
      unless rows.headers&.include?(id) && (rows.headers.include?("observation_date") || rows.headers.include?("DATE"))
        return invalid(result, "invalid_schema", "Official CSV did not contain the requested series and observation-date columns.")
      end
      observations = rows.map do |row|
        date = Date.iso8601(row["observation_date"] || row["DATE"])
        raise ArgumentError, "Future observation dates are not usable." if date > now.to_date
        raise ArgumentError, "Monthly observations must use the first day of the month." unless date.day == 1

        [date, row[id]]
      end.sort_by(&:first)
      return invalid(result, "missing_observation", "The source returned no observations.") if observations.empty?
      return invalid(result, "duplicate_observation", "The source returned duplicate observation dates.") unless observations.map(&:first).uniq.size == observations.size

      latest = observations.last
      value = positive_decimal(latest.last)
      return invalid(result, "invalid_value", "Latest published observation is missing, nonfinite or nonpositive.") unless value

      result.merge!("observation_date" => latest.first.iso8601, "value" => value.to_s("F"),
                    "observation_age_days" => (now.to_date - latest.first).to_i)
      prior = observations[-2]
      prior_value = prior && positive_decimal(prior.last)
      if prior_value
        result.merge!("prior_observation_date" => prior.first.iso8601, "prior_value" => prior_value.to_s("F"),
                      "change_pct" => ((value - prior_value) / prior_value * 100).round(6).to_s("F"))
      end
      if result["observation_age_days"] > @max_age_days
        result.merge("status" => "stale", "error" => { "code" => "overdue_observation", "message" => "Latest published observation exceeds the configured age limit; refresh does not make its observation date current." })
      else
        result.merge("status" => "available", "error" => nil)
      end
    rescue CSV::MalformedCSVError, ArgumentError, TypeError, KeyError => error
      invalid(result, "invalid_data", error.message)
    rescue StandardError => error
      invalid(result, "fetch_failed", "Market source could not be refreshed (#{error.class}).")
    end

    def positive_decimal(value)
      parsed = BigDecimal(value.to_s)
      parsed if parsed.finite? && parsed.positive?
    rescue ArgumentError
      nil
    end

    def invalid(result, code, message)
      result.merge("status" => "unavailable", "error" => { "code" => code, "message" => message })
    end
  end
end
