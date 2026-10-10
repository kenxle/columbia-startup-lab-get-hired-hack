# frozen_string_literal: true

module RfqProcessing
  # A matcher that follows the contract in docs/rfq_processing/RESULT-FORMAT.md,
  # so the pipeline runs end to end today. Tisch owns the real matching agent;
  # when it lands, the pipeline takes any object that responds to
  # `match(line_text:, spec:, quantity:, quantity_unit:)` and returns the same hash.
  #
  # Rules: an exact standard part number scores 1.0. A family without a dash
  # number is ambiguous. Metals need material, form, and grade to agree before
  # dimensions are scored. Nothing is substituted to force a match.
  class CatalogMatcher
    THRESHOLD = 0.8

    def initialize(rows)
      @rows = rows.map { |r| stringify(r) }
    end

    def self.from_json(path)
      new(JSON.parse(File.read(path)))
    end

    def match(line_text:, spec:, quantity: nil, quantity_unit: nil)
      spec = stringify(spec)
      if spec["part_number"]
        exact = @rows.select { |r| same_part?(r, spec["part_number"]) }
        return answer(exact.map { |r| candidate(r, 1.0, ["exact part number"], [], "Exact part number match.") }) if exact.any?
        return answer([], status: "no_match")
      end
      if spec["part_family"]
        family = @rows.select { |r| r["family"].to_s.casecmp?(spec["part_family"]) }
        family = family.select { |r| drilling_matches?(r, spec["drilling"]) } if spec["drilling"]
        cands = family.first(3).map { |r| candidate(r, 0.6, ["family", spec["drilling"]].compact, ["length not stated"], "Example of a #{spec['part_family']} length.") }
        return answer(cands, status: family.empty? ? "no_match" : "ambiguous", total: family.size)
      end

      scored = @rows.filter_map { |r| score_metal(r, spec) }.sort_by { |c| -c["score"] }
      answer(scored.first(3))
    end

    private

    def answer(cands, status: nil, total: nil)
      best = cands.first if cands.first && cands.first["score"] >= THRESHOLD
      status ||= if best.nil? then "no_match"
                 elsif cands.size > 1 && (cands[0]["score"] - cands[1]["score"]).abs < 0.05 then "ambiguous"
                 elsif best["score"] >= 1.0 then "exact"
                 else "scored"
                 end
      { "status" => status, "threshold" => THRESHOLD, "best" => status == "ambiguous" ? nil : best,
        "candidates" => cands, "total_candidates" => total || cands.size }
    end

    def candidate(row, score, matched_on, mismatches, reason)
      { "item_id" => row["item_id"] || row["pn"] || row["sku"] || row["id"], "part_number" => row["part_number"] || row["pn"],
        "description" => row["normalized_description"] || row["description"], "score" => score,
        "matched_on" => matched_on, "mismatches" => mismatches, "reason" => reason,
        "market_reference" => row["market_reference"], "observation_ids" => row["observation_ids"],
        "compliance" => row["compliance"], "purchase_unit" => row["purchase_unit"] || row["unit"],
        "list_price_usd_per_lb" => row["list_price_usd_per_lb"], "list_price_source" => row["list_price_source"], "catalog" => row["catalog"] }
    end

    def same_part?(row, part_number)
      wanted = part_number.to_s.upcase.delete(" ")
      [row["part_number"], *Array(row["rfq_aliases"])].compact.any? { |a| a.to_s.upcase.delete(" ") == wanted }
    end

    def drilling_matches?(row, drilling)
      case drilling
      when /undrilled/ then !row["shank_drilled"] && !row["head_drilled"]
      when /head/ then row["head_drilled"] == true
      when /drilled/ then row["shank_drilled"] == true
      else true
      end
    end

    # Metals: hard filters on material, form, grade; soft score on dimensions.
    def score_metal(row, spec)
      return nil unless row["material"] && spec["material"]
      return nil unless row["material"].to_s.casecmp?(spec["material"].to_s)
      return nil if row["form"] && spec["form"] && !row["form"].to_s.casecmp?(spec["form"].to_s)
      return nil if row["grade"] && spec["grade"] && !grade_fits?(row["grade"], spec["grade"])

      matched = ["material"]
      matched << "form" if row["form"]
      matched << "grade" if row["grade"]
      mismatches = []
      score = 0.5
      score += 0.15 if row["form"] && spec["form"]
      score += 0.2 if row["grade"] && spec["grade"]
      { "thickness_in" => 0.15, "width_in" => 0.1, "length_in" => 0.1 }.each do |key, weight|
        want = spec[key] || spec[key.sub("_in", "")]
        have = row[key] || row[key.sub("_in", "")]
        next unless want && have

        if (want.to_f - have.to_f).abs <= [0.002, want.to_f * 0.01].max
          score += weight
          matched << key.sub("_in", "")
        else
          mismatches << "#{key.sub('_in', '')} #{have} vs #{want}"
          score -= 0.3
        end
      end
      score = score.clamp(0.0, 1.0)
      candidate(row, score.round(2), matched, mismatches, mismatches.empty? ? "Material, form, grade, and size agree." : "Size differs: #{mismatches.join('; ')}.")
    end

    def grade_fits?(row_grade, wanted)
      a = row_grade.to_s.upcase
      b = wanted.to_s.upcase
      return true if a == b
      return true if a.include?("/") && a.split("/").map(&:strip).include?(b) # dual cert stock fills a single grade
      return false if b.end_with?("L") && !a.end_with?("L") && !a.include?("/") # 304L cannot be filled with plain 304

      false
    end

    def stringify(hash)
      hash.to_h.transform_keys(&:to_s)
    end
  end
end
