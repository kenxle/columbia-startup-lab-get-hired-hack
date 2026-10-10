module CatalogMatch
  # The matcher in the shape RFQ processing expects
  # (docs/rfq_processing/RESULT-FORMAT.md, "Contract with the matching agent").
  # Processing stays the single assembler of the result hash; it copies this
  # answer into processing.match.
  #
  #   CatalogMatch::Contract.call("line_text" => "...", "spec" => {...}, "client" => "Acme")
  #   => { "status" => "exact" | "scored" | "ambiguous" | "no_match", "threshold" => 0.8,
  #        "best" => {...} | nil, "candidates" => [...], "question" => "..." | nil }
  #
  # "client" is optional: when it names a known client, that client's memory
  # is used. "question" is an extra key processing may use as the buyer question.
  class Contract
    THRESHOLD = 0.8
    MAX_CANDIDATES = 3

    def self.call(input, workspace_token: nil, catalog: Catalog.default)
      input = input.to_h.deep_stringify_keys
      client = find_client(input["client"], workspace_token)
      given = input["spec"].to_h.merge(input.slice("quantity"))
      result = Matcher.call(input["line_text"].to_s, client: client, catalog: catalog, given: given)
      new(result).to_h
    end

    def self.find_client(name, workspace_token)
      return nil if name.blank? || workspace_token.blank?

      Client.for_workspace(workspace_token).find_by(name: name.to_s.squish)
    end

    def initialize(result)
      @result = result
    end

    def to_h
      entries = @result.candidates.first(MAX_CANDIDATES).map { |candidate| entry(candidate) }
      status = case @result.outcome
               when "no_match" then "no_match"
               when "match" then @result.best.checks.any? { |check| check[:field] == "pn" && check[:status] == :exact } ? "exact" : "scored"
               else entries.size > 1 ? "ambiguous" : "scored"
               end
      best = status == "no_match" || entries.empty? ? nil : entries.first
      best = nil if best && status == "scored" && best["score"] < THRESHOLD
      status = "no_match" if best.nil? && status != "ambiguous"
      {
        "status" => status,
        "threshold" => THRESHOLD,
        "best" => status == "ambiguous" ? nil : best,
        "candidates" => status == "exact" ? [] : entries,
        "question" => @result.question,
        "closest" => @result.closest.map { |candidate| entry(candidate) }
      }
    end

    private

    def entry(candidate)
      item = candidate.item
      {
        "item_id" => item["item_id"] || item["pn"],
        "part_number" => item["pn"],
        "description" => item["description"],
        "catalog" => item["catalog"],
        "catalog_provenance" => item["catalog_provenance"],
        "score" => (candidate.confidence / 100.0).round(2),
        "matched_on" => candidate.exact.map { |check| "#{check[:field]}: \"#{check[:buyer_text]}\"" },
        "mismatches" => (candidate.near + candidate.conflicts).map { |check| "#{check[:field]}: #{check[:explanation]}" },
        "reason" => reason(candidate)
      }
    end

    def reason(candidate)
      return "Every field the buyer wrote agrees with #{candidate.item['pn']}" if candidate.near.empty? && candidate.conflicts.empty?

      (candidate.near + candidate.conflicts).map { |check| check[:explanation] }.join("; ")
    end
  end
end
