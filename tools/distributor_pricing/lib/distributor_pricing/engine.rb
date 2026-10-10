# frozen_string_literal: true

require "bigdecimal"
require "time"
require "date"
require "uri"
require_relative "policy"

module DistributorPricing
  # Pure calculation over supplied evidence. No network, purchasing, or inferred fees.
  class Engine
    COST_FIELDS = %w[inbound_freight duty_brokerage supplier_certification outbound_freight handling financing_risk_reserve nonrecoverable_tax].freeze
    FRACTIONAL_UNITS = %w[lb lbs kg kilogram kilograms ton tons tonne tonnes ft foot feet m meter meters].freeze
    PRICE_SCOPE = "delivered_ex_tax"
    CHARGE_SCOPE = "all_required_charges_ex_tax"
    CENT = BigDecimal("0.01")

    def initialize(policy: Policy.new)
      @policy = policy
    end

    def price_line(item:, quantity:, unit:, destination:, offers:, benchmarks:, requirements: {}, now: Time.now.utc, delivery_by: nil)
      now = now.utc
      item = item.is_a?(Hash) ? item : {}
      requirements = requirements.is_a?(Hash) ? requirements : {}
      qty = quantity_number(quantity, unit)
      result = base_result(item, quantity, unit, destination, now)
      questions = result["buyer_questions"]
      questions << "Confirm a positive quantity for this sale unit; count units require whole numbers." unless qty&.positive?
      questions << "Confirm the sale unit." if blank?(unit)
      questions << "Provide the destination country and postal code." unless destination_valid?(destination)
      questions << "Confirm the exact part number before sourcing." if blank?(item["part_number"])
      deadline = parse_deadline(delivery_by)
      questions << "Confirm a valid future delivery date or timestamp." if delivery_by && (!deadline || deadline < now)
      unless questions.empty?
        result["status"] = "needs_buyer"
        result["reasons"] = questions.dup
        return result
      end

      assessments = Array(offers).map do |offer|
        assess_offer(offer, item, qty, unit, destination, requirements, now, deadline)
      end
      result["offer_assessments"] = assessments.map { |assessment| assessment.reject { |key, _| key.start_with?("_") } }
      candidates = assessments.select { |assessment| assessment["eligible"] }.map do |assessment|
        price_candidate(assessment, benchmarks, item, qty, unit, destination, requirements, now, deadline)
      end
      selected = candidates.min_by { |candidate| [candidate["status"] == "ready" ? 0 : 1, candidate["_cost"], candidate.dig("selected_offer", "id").to_s] }
      selected_evidence = selected && selected.delete("_offer")
      if selected
        selected.delete("_cost")
        result.merge!(selected)
      else
        result["procurement_tasks"] = assessments.flat_map { |assessment| assessment["reasons"].map { |reason| "#{assessment.dig('source', 'supplier') || assessment.dig('source', 'id') || 'Supplier'}: #{reason}" } }.uniq
        result["procurement_tasks"] << "Obtain an exact-part supplier offer with confirmed order terms and all line costs." if assessments.empty?
        indicative = assessments.select { |assessment| assessment["_indicative"] }.min_by { |assessment| assessment["_product_cost"] }
        if indicative
          result["indicative_product_only_price"] = {
            "unit_price" => money(indicative["_product_cost"] / qty), "currency" => indicative["source"]["currency"],
            "scope" => "supplier_product_acquisition_only", "is_selling_quote" => false,
            "includes_pack_overbuy" => true, "excludes" => COST_FIELDS + ["payment_fee", "profit_margin"],
            "source" => indicative["source"]
          }
        end
        result["reasons"] = result["procurement_tasks"].dup
      end
      result["quote_total"] = result["line_total"]
      result["procurement_plan"] = { "supplier" => result["selected_offer"], "cost_breakdown" => result["cost_breakdown"],
                                     "commercial_evidence" => selected_evidence && selected_evidence["commercial_evidence"],
                                     "supplier_offer_evidence" => selected_evidence }
      result
    end

    private

    def base_result(item, quantity, unit, destination, now)
      { "part_number" => item["part_number"], "quantity" => quantity, "unit" => unit,
        "destination" => destination, "calculated_at" => now.iso8601, "policy" => @policy.to_h,
        "status" => "needs_procurement", "unit_price" => nil, "line_total" => nil, "quote_total" => nil, "procurement_plan" => nil,
        "currency" => nil, "price_scope" => PRICE_SCOPE, "tax_treatment" => "excluded; assess separately before invoicing",
        "selected_offer" => nil, "quote_valid_until" => nil, "cost_breakdown" => nil,
        "pricing_analysis" => nil, "benchmark_comparisons" => [], "offer_assessments" => [],
        "indicative_product_only_price" => nil, "buyer_questions" => [], "procurement_tasks" => [], "reasons" => [] }
    end

    def assess_offer(offer, item, qty, unit, destination, requirements, now, deadline)
      offer = {} unless offer.is_a?(Hash)
      reasons = common_reasons(offer, item, unit, requirements, now)
      price = decimal(offer["unit_price"])
      reasons << "Confirm a positive supplier product unit price." unless price&.positive?
      pack = quantity_number(offer["pack_size"], unit)
      minimum = quantity_number(offer["minimum_quantity"], unit)
      reasons << "Confirm the pack size and item minimum quantity." unless pack&.positive? && minimum&.positive?
      purchase_qty = pack&.positive? && minimum&.positive? ? ([qty, minimum].max / pack).ceil * pack : nil
      reasons << "Confirm a price tier that covers the entire acquisition quantity." unless purchase_qty && tier_covers?(offer["tier"], purchase_qty)
      indicative = reasons.empty?
      product_cost = indicative ? up(price * purchase_qty) : nil
      reasons << "Verify public listing commercial terms with supplier evidence." unless offer["commercial_terms_verified"] == true && present?(offer["commercial_evidence"])
      expiry = parse_time(offer["valid_until"])
      reasons << "Obtain a supplier quote expiry in the future." unless expiry && expiry > now
      indicative = false if offer.key?("valid_until") && (!expiry || expiry <= now)
      stock = quantity_number(offer["stock_quantity"], unit)
      reasons << "Confirm sufficient stock for all purchased packs and MOQ units." unless offer["stock_confirmed"] == true && stock && purchase_qty && stock >= purchase_qty
      lead = integer(offer["lead_time_days"])
      reasons << "Confirm total calendar-day lead time through delivery to the buyer." unless lead && lead >= 0
      reasons << "Supplier cannot meet the requested delivery deadline." if deadline && lead && now + lead * 86_400 > deadline
      reasons << "Confirm shipping and charges for this exact destination." unless destination_equal?(offer["destination"], destination)
      conditions = offer["order_conditions"]
      unless conditions.is_a?(Hash) && conditions["line_sufficient"] == true && present?(conditions["evidence"])
        reasons << "Resolve supplier order minimums and multi-line conditions; this line alone is not confirmed sufficient."
      end
      costs = offer["costs"].is_a?(Hash) ? offer["costs"] : {}
      cost_values = {}
      COST_FIELDS.each do |field|
        value = costs[field]
        amount = value.is_a?(Hash) ? decimal(value["amount"]) : nil
        confirmed = value.is_a?(Hash) && value["confirmed"] == true && present?(value["evidence"]) && value["currency"] == offer["currency"]
        if amount && amount >= 0 && confirmed
          cost_values[field] = up(amount)
        else
          reasons << "Confirm #{field} amount, currency and evidence, including an explicit confirmed zero when applicable."
        end
      end
      fee = offer["payment_fee"]
      fee_rate = fee.is_a?(Hash) ? decimal(fee["rate"]) : nil
      unless fee_rate && fee_rate >= 0 && fee_rate < 1 - @policy.target_margin && fee["confirmed"] == true && present?(fee["evidence"])
        reasons << "Confirm a payment fee rate with evidence that leaves room for the target margin."
      end
      total_cost = reasons.empty? ? product_cost + cost_values.values.sum(BigDecimal("0")) : nil
      breakdown = { "product_acquisition" => product_cost && money(product_cost), "purchase_quantity" => quantity_value(purchase_qty),
                    "requested_quantity" => quantity_value(qty), "surplus_quantity" => purchase_qty && quantity_value(purchase_qty - qty),
                    "total_before_payment_fee" => total_cost && money(total_cost), "payment_fee_rate" => fee_rate&.to_s("F"),
                    "evidence" => costs, "payment_fee_evidence" => fee }
      COST_FIELDS.each { |field| breakdown[field] = cost_values[field] && money(cost_values[field]) }
      { "source" => source(offer), "eligible" => reasons.empty?, "reasons" => reasons,
        "cost_breakdown" => breakdown, "_offer" => offer, "_cost" => total_cost, "_fee_rate" => fee_rate,
        "_indicative" => indicative, "_product_cost" => product_cost }
    end

    def price_candidate(assessment, benchmarks, item, qty, unit, destination, requirements, now, deadline)
      offer = assessment["_offer"]
      cost, fee = assessment.values_at("_cost", "_fee_rate")
      target = floor_price(cost, qty, fee, @policy.target_margin)
      floor = floor_price(cost, qty, fee, @policy.minimum_margin)
      comparisons = Array(benchmarks).map { |benchmark| assess_benchmark(benchmark, offer, item, qty, unit, destination, requirements, now, deadline) }
      comparable = comparisons.select { |benchmark| benchmark["comparable"] }
      independent = comparable.map { |benchmark| benchmark.dig("source", "supplier").to_s.strip.downcase }.uniq.length
      # One observation per independent supplier prevents duplicate rows weighting the market.
      market = comparable.group_by { |benchmark| benchmark.dig("source", "supplier").to_s.strip.downcase }.values.map do |rows|
        rows.map { |benchmark| decimal(benchmark["total_price"]) / qty }.min
      end.sort
      low, high = market.first, market.last
      median = market.empty? ? nil : (market[(market.size - 1) / 2] + market[market.size / 2]) / 2
      status = "needs_procurement"
      tasks = []
      suggested = nil
      if independent < @policy.minimum_benchmark_suppliers
        tasks << "Obtain delivered quotes from at least #{@policy.minimum_benchmark_suppliers} independent suppliers for this exact part, quantity, destination and charge scope."
      elsif floor > median
        status = "not_competitive"
        tasks << "Find a lower landed acquisition cost or renegotiate terms; the minimum-margin floor exceeds the median comparable delivered market offer."
      else
        market_total_cap = (median * qty).round(2, BigDecimal::ROUND_FLOOR)
        suggested = [target, (market_total_cap / qty).round(2, BigDecimal::ROUND_FLOOR)].min
        status = "ready"
        # A fractional sale quantity can leave a fractional cent on the line total.
        if suggested < floor
          suggested = nil
          status = "not_competitive"
          tasks << "Rounded delivered line total cannot meet the market median while preserving the minimum-margin floor."
        end
      end
      revenue = suggested && up(suggested * qty)
      payment_cost = revenue && up(revenue * fee)
      margin = revenue && (revenue - cost - payment_cost) / revenue
      caps = [now + @policy.quote_validity_seconds, parse_time(offer["valid_until"]), parse_time(offer["retrieved_at"]) + @policy.max_source_age_seconds]
      comparable.each do |benchmark|
        caps << parse_time(benchmark.dig("source", "retrieved_at")) + @policy.max_source_age_seconds
        caps << parse_time(benchmark.dig("source", "valid_until"))
      end
      caps << deadline - offer["lead_time_days"].to_i * 86_400 if deadline
      if suggested && caps.compact.min <= now
        status = "needs_procurement"
        tasks << "Delivery deadline leaves no time to accept this quote; reconfirm lead time or the delivery deadline."
        suggested = revenue = payment_cost = margin = nil
      end
      { "status" => status, "unit_price" => suggested && money(suggested), "line_total" => revenue && money(revenue),
        "currency" => offer["currency"], "selected_offer" => source(offer),
        "quote_valid_until" => suggested && caps.compact.min.iso8601,
        "cost_breakdown" => assessment["cost_breakdown"].merge("payment_fee" => payment_cost && money(payment_cost), "total_cost" => payment_cost && money(cost + payment_cost)),
        "pricing_analysis" => { "target_unit_price" => money(target), "minimum_unit_price" => money(floor),
                                "realized_margin" => margin&.round(8, BigDecimal::ROUND_FLOOR)&.to_s("F"),
                                "market_low_unit_price" => low&.to_s("F"), "market_median_unit_price" => median&.to_s("F"),
                                "market_high_unit_price" => high&.to_s("F"), "independent_benchmark_suppliers" => independent,
                                "comparison_basis" => "At or below the median of independent delivered supplier quotes, excluding tax; not a claim to be cheapest.",
                                "at_or_below_market_low" => revenue && revenue <= low * qty,
                                "at_or_below_market_median" => revenue && revenue <= median * qty,
                                "at_or_below_market_high" => revenue && revenue <= high * qty,
                                "formula" => "cost / quantity / (1 - margin - payment_fee_rate); round up cents and verify rounded payment fee",
                                "competitive" => suggested ? true : (status == "not_competitive" ? false : nil) },
        "benchmark_comparisons" => comparisons, "procurement_tasks" => tasks, "reasons" => tasks.dup,
        "_cost" => cost, "_offer" => offer }
    end

    def assess_benchmark(benchmark, offer, item, qty, unit, destination, requirements, now, deadline)
      benchmark = {} unless benchmark.is_a?(Hash)
      reasons = common_reasons(benchmark, item, unit, requirements, now)
      reasons << "Currency differs from sourcing currency." unless benchmark["currency"] == offer["currency"]
      reasons << "Benchmark item condition differs from sourced condition." unless benchmark["condition"] == offer["condition"]
      reasons << "Benchmark quantity or price tier does not cover the requested quantity." unless quantity_number(benchmark["quantity"], unit) == qty && tier_covers?(benchmark["tier"], qty)
      stock = quantity_number(benchmark["stock_quantity"], unit)
      pack, minimum = quantity_number(benchmark["pack_size"], unit), quantity_number(benchmark["minimum_quantity"], unit)
      acquired = pack&.positive? && minimum&.positive? ? ([qty, minimum].max / pack).ceil * pack : nil
      unless benchmark["stock_confirmed"] == true && stock && acquired && stock >= acquired && tier_covers?(benchmark["tier"], acquired)
        reasons << "Benchmark stock, packs, MOQ or acquisition price tier is unconfirmed."
      end
      conditions = benchmark["order_conditions"]
      unless conditions.is_a?(Hash) && conditions["line_sufficient"] == true && present?(conditions["evidence"])
        reasons << "Benchmark order-level conditions are unresolved."
      end
      reasons << "Benchmark is not an all-required-charges delivered comparison excluding tax." unless benchmark["price_scope"] == PRICE_SCOPE && benchmark["charge_scope"] == CHARGE_SCOPE
      reasons << "Benchmark destination differs." unless destination_equal?(benchmark["destination"], destination)
      total = decimal(benchmark["total_price"])
      reasons << "Benchmark requires a positive total price." unless total&.positive?
      reasons << "Benchmark delivery/charge terms need confirmation." unless benchmark["commercial_terms_verified"] == true && present?(benchmark["commercial_evidence"])
      expiry = parse_time(benchmark["valid_until"])
      reasons << "Benchmark validity is expired or unknown." unless expiry && expiry > now
      lead = integer(benchmark["lead_time_days"])
      reasons << "Benchmark delivery timing is unknown or misses deadline." unless lead && lead >= 0 && (!deadline || now + lead * 86_400 <= deadline)
      { "source" => source(benchmark), "comparable" => reasons.empty?, "reasons" => reasons,
        "total_price" => total&.to_s("F"), "price_scope" => benchmark["price_scope"], "charge_scope" => benchmark["charge_scope"] }
    end

    def common_reasons(record, item, unit, requirements, now)
      reasons = []
      reasons << "Exact part number differs or is absent; substitution is not authorized." unless record["part_number"] == item["part_number"]
      reasons << "Confirm supplier identity and supplier SKU." if blank?(record["supplier"]) || blank?(record["supplier_sku"])
      reasons << "Provide an HTTP(S) supplier source URL." unless http_url?(record["source_url"])
      retrieved = parse_time(record["retrieved_at"])
      reasons << "Source timestamp is missing, future-dated or stale." unless retrieved && retrieved <= now && now - retrieved < @policy.max_source_age_seconds
      reasons << "Confirm an explicit three-letter currency." unless record["currency"].is_a?(String) && record["currency"].match?(/\A[A-Z]{3}\z/)
      reasons << "Sale unit differs or is absent." unless record["unit"] == unit
      [item["specs"], requirements["specs"]].select { |specs| specs.is_a?(Hash) }.each do |expected_specs|
        expected_specs.each do |key, value|
          reasons << "Specification #{key} is missing or differs." unless !value.nil? && record["specs"].is_a?(Hash) && record["specs"][key] == value
        end
      end
      conditions = [requirements["condition"], item["condition"]].compact
      reasons << "Item condition is unconfirmed or differs." if blank?(record["condition"]) || conditions.any? { |condition| record["condition"] != condition }
      missing = Array(requirements["certifications"]) - Array(record["certifications"])
      reasons << "Required certifications missing: #{missing.join(', ')}." unless missing.empty?
      origins = Array(requirements["allowed_origins"])
      reasons << "Origin is unconfirmed or not allowed." if !origins.empty? && !origins.include?(record["origin"])
      reasons
    end

    def source(record)
      record.slice("id", "supplier", "part_number", "supplier_sku", "source_url", "quote_url", "buy_url", "retrieved_at", "valid_until", "currency", "unit")
    end

    def floor_price(cost, qty, fee, margin)
      price = up(cost / qty / (1 - margin - fee))
      loop do
        revenue = up(price * qty)
        break if (revenue - cost - up(revenue * fee)) / revenue >= margin

        price += CENT
      end
      price
    end

    def tier_covers?(tier, quantity)
      return false unless tier.is_a?(Hash) && tier.key?("max")

      minimum, maximum = decimal(tier["min"]), decimal(tier["max"])
      minimum && minimum.positive? && quantity >= minimum && (tier["max"].nil? || (maximum && quantity <= maximum))
    end

    def decimal(value)
      return nil unless value.is_a?(String) || value.is_a?(Numeric)

      parsed = BigDecimal(value.to_s)
      parsed if parsed.finite?
    rescue ArgumentError, TypeError
      nil
    end

    def integer(value)
      parsed = decimal(value)
      parsed.to_i if parsed && parsed.frac.zero?
    end

    def quantity_number(value, unit)
      parsed = decimal(value)
      parsed if parsed && (FRACTIONAL_UNITS.include?(unit.to_s.downcase) || parsed.frac.zero?)
    end

    def quantity_value(value)
      return nil unless value

      value.frac.zero? ? value.to_i : value.to_s("F")
    end

    def up(value)
      value.round(2, BigDecimal::ROUND_CEILING)
    end

    def money(value)
      whole, fraction = up(value).to_s("F").split(".")
      "#{whole}.#{fraction.to_s.ljust(2, '0')}"
    end

    def parse_time(value)
      Time.iso8601(value).utc if value.is_a?(String)
    rescue ArgumentError
      nil
    end

    def parse_deadline(value)
      return nil if value.nil?
      return Time.utc(*Date.iso8601(value).to_s.split("-").map(&:to_i)) + 86_399 if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      parse_time(value)
    rescue ArgumentError
      nil
    end

    def http_url?(value)
      uri = URI.parse(value) if value.is_a?(String)
      uri && %w[http https].include?(uri.scheme) && present?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def destination_valid?(value)
      value.is_a?(Hash) && present?(value["country"]) && present?(value["postal_code"])
    end

    def destination_equal?(left, right)
      destination_valid?(left) && destination_valid?(right) && left == right
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def present?(value)
      !blank?(value)
    end
  end
end
