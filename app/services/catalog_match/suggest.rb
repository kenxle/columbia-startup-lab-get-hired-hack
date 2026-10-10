module CatalogMatch
  # Runs the matcher for one client and saves the request with its suggestions.
  class Suggest
    def self.call(client:, description:, catalog: Catalog.default)
      result = Matcher.call(description, client: client, catalog: catalog)
      quantity = result.reading["quantity"]
      client.match_requests.create!(
        description: description,
        outcome: result.outcome,
        quantity: quantity,
        result: serialize(result)
      )
    end

    def self.serialize(result)
      {
        "question" => result.question,
        "reading" => result.reading.fields,
        "notes" => result.reading.notes,
        "unknown_words" => result.reading.unknown_words,
        "candidates" => result.candidates.map { |candidate| serialize_candidate(candidate) },
        "closest" => result.closest.map { |candidate| serialize_candidate(candidate) }
      }
    end

    def self.serialize_candidate(candidate)
      {
        "pn" => candidate.item["pn"],
        "description" => candidate.item["description"],
        "confidence" => candidate.confidence,
        "checks" => candidate.checks.map { |check| check.transform_keys(&:to_s).transform_values { |value| value.is_a?(Symbol) ? value.to_s : value } }
      }
    end
  end
end
