# frozen_string_literal: true

require "digest"
require "date"
require "uri"

module RfqProcessing
  # Turns a Reading, a match, a decision, and compliance flags into one line of
  # the result hash. Shape: docs/rfq_processing/RESULT-FORMAT.md. Limits come
  # from the app's QuoteLine model.
  module ResultBuilder
    # Internal field name => app spec key. Hirsh's eight keys first, then extensions.
    SPEC_MAP = {
      "material" => "material", "grade" => "grade", "form" => "form", "thickness_in" => "thickness", "wall_in" => "thickness",
      "width_in" => "width", "side_a_in" => "width", "length_in" => "length", "standard" => "standard", "finish" => "finish",
      "part_number" => "part_number", "part_family" => "part_family", "diameter_in" => "diameter", "nominal_size_in" => "diameter",
      "side_b_in" => "side_b", "schedule" => "schedule", "temper" => "temper", "coating" => "coating", "process" => "process",
      "thread" => "thread", "grip" => "grip", "drilling" => "drilling", "gauge" => "gauge"
    }.freeze

    LIMITS = { "description" => 500, "original_text" => 5_000, "price_source" => 200, "clarification_question" => 1_000,
               "notes" => 2_000, "catalog_sku" => 100 }.freeze

    # The internal field behind an app spec key. The first mapping wins: "thickness" is thickness_in, not wall_in.
    def self.internal_field(key)
      SPEC_MAP.key(key.to_s) || key.to_s
    end

    def self.line_id(position, original_text)
      "line-#{position}-#{Digest::SHA256.hexdigest(original_text)[0, 8]}"
    end

    def self.build(reading:, decision:, match:, compliance:, position:, original_text:, location:)
      f = reading.fields
      spec = {}
      evidence = {}
      confidence = {}
      SPEC_MAP.each do |internal, key|
        value = f[internal]
        next if value.nil? || spec.key?(key)

        spec[key] = value.is_a?(Float) || value.is_a?(Integer) ? Units.tidy(value.to_f) : value.to_s
        ev = reading.evidence[internal]
        evidence[key] = ev ? ev.dup : { "text" => original_text[0, 200], "location" => location, "explanation" => "from the line as a whole" }
        confidence[key] = reading.confidence[internal] if reading.confidence[internal]
      end
      if f["quantity"]
        evidence["quantity"] = reading.evidence["quantity"] || { "text" => original_text[0, 200], "location" => location, "explanation" => "quantity" }
        confidence["quantity"] = reading.confidence["quantity"] if reading.confidence["quantity"]
      end

      best = match && match["best"]
      ready = decision.state == "ready" && best
      price = ready ? price_for(best, quantity_unit: f["quantity_unit"]) : nil
      line_id = line_id(position, original_text)
      choices = decision.choices.each_with_index.map { |c, i| { "id" => "#{line_id}-c#{i + 1}" }.merge(c) }
      state = decision.state
      question = decision.question
      unresolved = decision.unresolved_fields
      if ready && price.nil?
        # Matched, but the catalog has no price yet (Tisch's pricer is pending). The app has no
        # "waiting for price" state, so the line is held with unit_price unresolved, as Tisch's AddToQuote does.
        state = "needs_buyer"
        unresolved = ["unit_price"]
        question = "Line #{position} is matched to #{best['part_number'] || best['item_id']}. The price is to be confirmed by the rep before this line can be quoted."
        ready = false
      end

      {
        "line_id" => line_id,
        "position" => position,
        "description" => clip(describe(f, best), "description"),
        "original_text" => clip(original_text, "original_text"),
        "spec" => spec,
        "quantity" => f["quantity"],
        "quantity_unit" => f["quantity_unit"],
        "catalog_sku" => best && state != "no_match" ? clip(best["item_id"].to_s, "catalog_sku") : nil,
        "unit_price" => price && price[:unit_price],
        "price_source" => price && clip(price[:source], "price_source"),
        "state" => state,
        "clarification_question" => question && clip(question, "clarification_question"),
        "notes" => clip(notes_for(reading, match, decision), "notes"),
        "evidence" => evidence,
        "compliance" => compliance.map { |c| c.slice("label", "evidence", "note") },
        "benchmark" => ready ? benchmark_for(best) : nil,
        "unresolved_fields" => unresolved.map { |u| SPEC_MAP[u] || u }.uniq,
        "edited_fields" => [],
        "processing" => {
          "confidence" => confidence,
          "assumptions" => reading.assumptions.uniq,
          "rules_used" => reading.rules_used.uniq,
          "conflicts" => reading.conflicts,
          "match" => match && match.slice("status", "score", "reason", "threshold", "candidates").merge(
            "score" => best ? best["score"] : (match["candidates"].first&.[]("score") || 0.0),
            "reason" => best ? best["reason"] : (match["candidates"].first&.[]("reason") || "No candidate reached the threshold.")
          ),
          "question_choices" => choices,
          "alternates" => alternates_for(match, choices, line_id, f, decision.unresolved_fields),
          "compliance_detail" => compliance,
          "lead_time" => lead_time_for(best)
        }
      }
    end

    # Spec keys a candidate may carry (the catalog row's fields, in the internal names).
    CANDIDATE_SPEC = %w[material grade temper form thickness_in wall_in width_in length_in diameter_in finish standard coating part_number gauge].freeze

    # Alternates on an ambiguous line (RESULT-FORMAT.md, "Alternates on ambiguous lines"): one option per
    # candidate at or above the threshold, in the matcher's order, priced only from a labeled source by the
    # same rules as the line. Every other line gets []. A no match line's closest items are never options.
    def self.alternates_for(match, choices, line_id, f, unresolved_fields)
      return [] unless match && match["status"] == "ambiguous"

      # An option resolves which item, not missing demand or conflicting specs.
      remaining = Array(unresolved_fields).map { |field| SPEC_MAP[field] || field } - ["catalog item", "catalog_item"]
      threshold = (match["threshold"] || 0.8).to_f
      Array(match["candidates"]).select { |c| c.is_a?(Hash) && c["score"].to_f >= threshold && Array(c["mismatches"]).empty? }.each_with_index.map do |c, i|
        choice = choices.find { |ch| ch["field"] == "catalog_item" && ch["value"].to_s == c["item_id"].to_s }
        price = price_for(c, quantity_unit: f["quantity_unit"])
        lead = lead_time_for(c)
        {
          "id" => "#{line_id}-o#{i + 1}",
          "choice_id" => choice && choice["id"],
          "label" => "Option #{(65 + i).chr}: #{c['description'] || c['part_number'] || c['item_id']}"[0, 200],
          "catalog_sku" => clip(c["item_id"].to_s, "catalog_sku"),
          "item_id" => c["item_id"],
          "spec" => c.slice(*CANDIDATE_SPEC).reject { |_, v| v.nil? },
          "quantity" => f["quantity"],
          "quantity_unit" => f["quantity_unit"],
          "unit_price" => price && price[:unit_price],
          "currency" => price ? "USD" : nil,
          "price_source" => price && clip(price[:source], "price_source"),
          "benchmark" => price ? benchmark_for(c) : nil,
          "lead_time" => lead["text"],
          "lead_time_source" => lead["source"],
          "unresolved_fields" => remaining | (price ? [] : ["unit_price"])
        }
      end
    end

    def self.describe(f, best)
      return best["description"] if best && best["description"]

      dims = []
      t = f["thickness_in"] || f["wall_in"]
      dims << "#{t} in#{f['gauge'] ? " (#{f['gauge']} ga)" : ''}#{f['wall_in'] ? ' wall' : ''}" if t
      dims << "#{f['side_a_in']} x #{f['side_b_in']} in" if f["side_a_in"] && f["side_b_in"]
      dims << "#{f['diameter_in']} in dia" if f["diameter_in"]
      dims << "#{f['nominal_size_in']} in sch #{f['schedule']}" if f["nominal_size_in"]
      dims << "#{f['width_in']} in x #{f['length_in']} in" if f["width_in"] && f["length_in"]
      dims << "#{f['width_in']} in wide" if f["width_in"] && !f["length_in"]
      dims << "#{f['length_in']} in long" if f["length_in"] && !f["width_in"] && !(f["side_a_in"] || f["diameter_in"] || f["nominal_size_in"])
      dims << "#{f['length_in']} in long" if f["length_in"] && (f["side_a_in"] || f["diameter_in"] || f["nominal_size_in"])
      head = [f["material"]&.capitalize, f["grade"], f["temper"], f["form"] || f["part_number"] || f["part_family"]].compact.join(" ")
      tail = [f["standard"], f["finish"], f["coating"]].compact.join(", ")
      [head, dims.join(", "), tail].reject(&:empty?).join(", ")
    end

    def self.price_for(best, quantity_unit: nil)
      return sourced_price(best["price"], quantity_unit: quantity_unit) if best.key?("price")

      ref = best["market_reference"]
      if supported_dealer_reference?(best) && %w[each ea pc piece].include?(quantity_unit.to_s.downcase)
        obs = Array(best["observation_ids"]).join(", ")
        return { unit_price: ref["midpoint_usd_each"],
                 source: "Two-dealer midpoint, single piece, product only (#{obs}), USD #{ref['min_usd_each']} to #{ref['max_usd_each']}, observed #{observation_date(best) || 'date unknown'}." }
      end
      list = best["list_price_usd_per_lb"]
      if list && quantity_unit.to_s.downcase == "lb" && valid_usd_price?(list, best["list_price_source"] || {})
        src = best["list_price_source"] || {}
        return nil unless valid_source_url?(src["url"]) || !src["kind"].to_s.strip.empty?

        return { unit_price: list,
                 source: "#{[src['kind'], src['text'], (src['url'] if valid_source_url?(src['url']))].compact.join(' ')}, per lb, observed #{observation_date(best) || 'date unknown'}." }
      end
      nil
    end

    def self.valid_source_url?(value)
      uri = URI.parse(value.to_s)
      %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?
    rescue URI::InvalidURIError
      false
    end

    def self.supported_dealer_reference?(best)
      ref = best["market_reference"]
      return false unless ref.is_a?(Hash) && ref["source_count"].to_i >= 2
      return false unless Array(best["observation_ids"]).map(&:to_s).reject { |id| id.strip.empty? }.uniq.size >= 2
      return false unless %w[min_usd_each midpoint_usd_each max_usd_each].all? { |key| valid_usd_price?(ref[key], ref) }
      return false unless Float(ref["midpoint_usd_each"]).between?(Float(ref["min_usd_each"]), Float(ref["max_usd_each"]))

      Date.iso8601(observation_date(best).to_s)
      true
    rescue Date::Error
      false
    end

    # Tisch's candidate price carries an explicit basis. The quote app is USD
    # only, so another currency or sale unit stays held, without conversion.
    def self.sourced_price(price, quantity_unit:)
      return nil unless price.is_a?(Hash) && price["currency"] == "USD"

      benchmark = price["benchmark"]
      return nil unless benchmark.is_a?(Hash)
      return nil unless %w[name as_of kind unit explanation].all? { |key| !benchmark[key].to_s.strip.empty? }
      return nil if price["price_source"].to_s.strip.empty?
      return nil unless valid_usd_price?(price["unit_price"], price)

      unit = quantity_unit.to_s.downcase
      basis = benchmark["unit"].to_s.downcase.strip
      return nil unless ["usd per #{unit}", "usd #{unit}"].include?(basis) && !unit.empty?
      Date.iso8601(benchmark["as_of"].to_s)
      { unit_price: Float(price["unit_price"]), source: price["price_source"] }
    rescue Date::Error
      nil
    end

    def self.valid_usd_price?(value, source)
      price = Float(value, exception: false)
      price && price.finite? && price.positive? && (!source["currency"] || source["currency"] == "USD")
    end

    # Never relabel an undated listing as observed on the processing day.
    def self.observation_date(best)
      source = best["market_reference"] || best["list_price_source"] || {}
      source["as_of"] || source["observed_at"] || source["observation_date"] || best["observed_at"] || best["observation_date"]
    end

    def self.benchmark_for(best)
      if best["price"].is_a?(Hash) && best["price"]["benchmark"].is_a?(Hash)
        benchmark = best["price"]["benchmark"].dup
        benchmark["kind"] = { "website_list_price" => "list_price", "dealer_listing_midpoint" => "dealer_midpoint" }.fetch(benchmark["kind"], benchmark["kind"])
        return benchmark
      end

      ref = best["market_reference"]
      if ref.nil? && best["list_price_usd_per_lb"]
        src = best["list_price_source"] || {}
        return { "name" => "#{src['kind'] || 'Catalog list reference'} for #{best['part_number'] || best['item_id']}", "as_of" => observation_date(best),
                 "unit" => "USD per lb", "kind" => "list_price",
                 "explanation" => "#{src['kind'] || 'Catalog list reference'} (#{src['text']}). Supports a list reference for this item. Does not support a negotiated, bulk, or delivered price." }
      end
      return nil unless ref

      { "name" => "Public dealer listings for #{best['part_number'] || best['item_id']} (#{ref['source_count']} sources)",
        "as_of" => observation_date(best), "unit" => "USD each", "kind" => "dealer_midpoint",
        "explanation" => "#{ref['interpretation'] || 'Two public dealer listings, single-piece price'}. Supports a retail reference for this part. Does not support a delivered price, a bulk tier, or a market index." }
    end

    # Ken, 13:31: items the catalog marks as stocked get RudCo's 24 to 48 hour promise; anything else is "to confirm".
    def self.lead_time_for(best)
      stock = best && (best["stock"] || {})
      stocked = stock && (stock["stock_reported"] == true || stock["in_stock"] == true)
      if stocked
        { "text" => "24 to 48 hours", "stocked" => true,
          "source" => "catalog row marks the item in stock (#{stock['stock_scope'] || 'stock reported'}); RudCo's stated shipping promise for stocked items" }
      else
        { "text" => "to confirm", "stocked" => false, "source" => best ? "no stock confirmation on the catalog row" : "no catalog match" }
      end
    end

    def self.notes_for(reading, match, decision)
      parts = []
      parts << "Assumptions: #{reading.assumptions.uniq.join(' ')}" if reading.assumptions.any?
      parts << "Rules used: #{reading.rules_used.uniq.join('; ')}." if reading.rules_used.any?
      if match && decision.state == "no_match"
        parts << "No match in the current catalog. #{match['candidates'].first&.[]('reason')}".strip
      end
      best = match && match["best"]
      parts << "Price basis is one piece; the quantity tier was not collected. The rep confirms the final price." if best && best["market_reference"]
      parts.join(" ")
    end

    def self.clip(text, key)
      return nil if text.nil?

      limit = LIMITS[key] || 1_000
      text.length > limit ? "#{text[0, limit - 1]}…" : text
    end
  end
end
