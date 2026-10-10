# frozen_string_literal: true

require "digest"

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
      price = ready ? price_for(best) : nil
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
          "compliance_detail" => compliance
        }
      }
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

    def self.price_for(best)
      ref = best["market_reference"]
      if ref && ref["midpoint_usd_each"]
        obs = Array(best["observation_ids"]).join(", ")
        return { unit_price: ref["midpoint_usd_each"],
                 source: "Two-dealer midpoint, single piece, product only (#{obs}), USD #{ref['min_usd_each']} to #{ref['max_usd_each']}. Sample data." }
      end
      list = best["list_price_usd_per_lb"]
      if list
        src = best["list_price_source"] || {}
        return { unit_price: list,
                 source: "#{src['kind'] || 'Website list price'} #{src['text']} (#{src['url'] || 'rud-co.com'}), per lb, not confirmed by RudCo. Sample data." }
      end
      nil
    end

    def self.benchmark_for(best)
      ref = best["market_reference"]
      if ref.nil? && best["list_price_usd_per_lb"]
        src = best["list_price_source"] || {}
        return { "name" => "#{src['kind'] || 'Website list price'} for #{best['part_number'] || best['item_id']}", "as_of" => "2026-10-10",
                 "unit" => "USD per lb", "kind" => "sample",
                 "explanation" => "RudCo's own published list price (#{src['text']}). Supports a list reference for this item. Does not support a negotiated, bulk, or delivered price." }
      end
      return nil unless ref

      { "name" => "Public dealer listings for #{best['part_number'] || best['item_id']} (#{ref['source_count']} sources)",
        "as_of" => "2026-10-10", "unit" => "USD each", "kind" => "sample",
        "explanation" => "#{ref['interpretation'] || 'Two public dealer listings, single-piece price'}. Supports a retail reference for this part. Does not support a delivered price, a bulk tier, or a market index." }
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
