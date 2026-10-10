# frozen_string_literal: true

module RfqProcessing
  # Two explicit alternatives are two separate catalog checks, not permission
  # to substitute one abrasive size for another. The buyer must choose.
  module AbrasiveAlternatives
    GRADE = /\b[SG]\s*-?\s*\d{2,3}\b/i
    PAIR = /\b([SG])\s*-?\s*(\d{2,3})\s+or\s+([SG])\s*-?\s*(\d{2,3})\b/i

    def self.match(text:, reading:, matcher:, position:, location:, buyer_terms: [], overrides: {})
      pair = PAIR.match(text)
      return nil unless pair && reading.fields["form"] == "abrasive"

      unless pair[1].casecmp?(pair[3]) && text.scan(GRADE).size == 2 && text.scan(/\bor\b/i).size == 1
        reading.conflicts << { "code" => "abrasive_alternatives_unsupported", "fields" => ["grade"],
          "message" => "The line names different abrasive families or more than two alternatives. Please confirm the required grade." }
        return nil
      end
      grades = ["#{pair[1].upcase}-#{pair[2]}", "#{pair[3].upcase}-#{pair[4]}"].uniq
      return nil unless grades.size == 2

      candidates = grades.filter_map do |grade|
        branch_text = text.sub(PAIR, grade)
        branch = RulesParser.parse(branch_text, position: position, location: location, buyer_terms: buyer_terms, overrides: overrides)
        next unless branch.conflicts.empty? && branch.unknowns.empty?
        next unless branch.fields["quantity"] == reading.fields["quantity"] && branch.fields["quantity_unit"] == reading.fields["quantity_unit"]
        next unless branch.fields["grade"] == grade

        match = matcher.match(line_text: branch_text, spec: branch.fields.compact,
          quantity: branch.fields["quantity"], quantity_unit: branch.fields["quantity_unit"])
        candidate = match["best"]
        next unless %w[exact scored].include?(match["status"]) && candidate.is_a?(Hash)
        next unless candidate["score"].to_f >= (match["threshold"] || 0.8).to_f && Array(candidate["mismatches"]).empty?
        next unless candidate["grade"] == grade

        candidate
      end.uniq { |candidate| candidate["item_id"] }
      # The original line must not claim that the first grade was selected.
      reading.fields.delete("grade")
      reading.evidence.delete("grade")
      reading.confidence.delete("grade")
      reading.rules_used << "Explicit abrasive alternatives: #{grades.join(' or ')}; buyer choice required."
      { "status" => "ambiguous", "threshold" => 0.8, "best" => nil, "candidates" => candidates,
        "total_candidates" => candidates.size, "question" => "Which abrasive grade is required: #{grades.join(' or ')}?" }
    end

    def self.apply_choice(reading, match, text, location)
      return unless match["status"] == "exact" && match["best"]
      grade = match["best"]["grade"]
      hit = text.to_enum(:scan, GRADE).map { Regexp.last_match }.find { |found| found[0].delete(" -").upcase == grade.delete("-") }
      return unless hit

      reading.fields["grade"] = grade
      reading.confidence["grade"] = 1.0
      reading.evidence["grade"] = { "text" => hit[0], "location" => "#{location}, chars #{hit.begin(0) + 1}-#{hit.end(0)}",
        "explanation" => "The buyer chose this explicitly requested abrasive grade from the validated catalog alternatives." }
    end
  end
end
