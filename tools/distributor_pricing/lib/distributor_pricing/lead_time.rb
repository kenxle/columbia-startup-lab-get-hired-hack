# frozen_string_literal: true

module DistributorPricing
  module LeadTime
    POLICY_URL = "https://www.aircraftspruce.com/terms_conditions.php"

    def self.for_line(pricing:, source:, quantity:)
      offer = pricing.dig("procurement_plan", "supplier_offer_evidence")
      raw_days = offer["lead_time_days"] if offer.is_a?(Hash)
      days = raw_days.to_i if (raw_days.is_a?(Integer) || raw_days.is_a?(String)) && raw_days.to_s.match?(/\A\d+\z/)
      if offer.is_a?(Hash) && offer["commercial_terms_verified"] == true && offer["stock_confirmed"] == true && !days.nil?
        return { "status" => "supplier_confirmed", "total_calendar_days" => days,
                 "text" => "#{days} calendar days after order acceptance, through delivery",
                 "supplier" => offer["supplier"], "source_url" => offer["quote_url"] || offer["source_url"],
                 "checked_at" => offer["retrieved_at"], "valid_until" => offer["valid_until"],
                 "destination" => offer["destination"], "is_delivery_commitment" => false,
                 "assumptions" => ["Order accepted within current supplier quote validity; allocation and delivery terms reconfirmed at order."] }
      end
      context = source["dispatch_policy"] || {}
      listed = Array(source["offers"]).find { |row| row["supplier"] == "Aircraft Spruce" && row["stock_quantity"].to_f >= quantity.to_f && quantity.to_f.positive? }
      if context["ok"] && context["verified_same_day_policy"] && listed
        return { "status" => "partial_estimate", "total_calendar_days" => nil,
                 "text" => "Supplier normally dispatches in-stock UPS orders the same business day before its 4 pm local cutoff; delivery to confirm",
                 "supplier_dispatch_business_days" => 0, "transit_days" => nil,
                 "supplier" => "Aircraft Spruce", "source_url" => POLICY_URL, "checked_at" => context["retrieved_at"],
                 "stock_source_url" => listed["source_url"], "is_delivery_commitment" => false,
                 "assumptions" => ["Public stock is not an allocation", "UPS service and origin-warehouse weekday/cutoff must apply", "Holidays, dropship, certifications and capacity can delay dispatch", "Distributor receiving/handling and destination-specific transit are not confirmed"] }
      end
      { "status" => "needs_supplier_confirmation", "total_calendar_days" => nil,
        "text" => "Lead time to confirm with supplier", "is_delivery_commitment" => false,
        "assumptions" => ["Exact SKU stock/allocation, manufacturing or backorder, paperwork, handling, shipping service and destination transit require current supplier evidence"] }
    end
  end
end
