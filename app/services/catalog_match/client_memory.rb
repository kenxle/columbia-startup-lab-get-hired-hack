module CatalogMatch
  # One client's memory of what its words mean. Every client has its own terms,
  # so "KB" can mean a #4 finish for one company and 316L for another.
  #
  # It learns two things when the rep approves an item for a client:
  # 1. The whole description (minus the quantity) maps to the approved part
  #    number, so the same request next time goes straight to that item.
  # 2. Each word the reader did not understand maps to the approved item's
  #    values for the fields the description left out.
  # The rep can also teach a meaning directly. Taught terms are never
  # overwritten by learning.
  class ClientMemory
    LEARNED_FIELDS = %w[material grade temper form finish].freeze
    MAXIMUM_PHRASE_LENGTH = 120

    def initialize(client)
      @client = client
    end

    # Longest terms first, so a remembered phrase wins over a word inside it.
    def terms
      @client.client_terms.to_a.sort_by { |term| [ -term.term.length, term.term ] }
    end

    def teach!(term:, field: nil, value: nil, part_number: nil)
      record = @client.client_terms.find_or_initialize_by(term: ClientTerm.normalize_value_for(:term, term))
      meaning = {}
      meaning["fields"] = { field.to_s => value.to_s.strip } if field.present? && value.present?
      meaning["part_number"] = part_number.to_s.upcase if part_number.present?
      record.assign_attributes(meaning: meaning, source: "taught", times_confirmed: 1)
      record.save!
      record
    end

    # Returns the terms created or updated by this approval.
    def learn!(match_request:, item:)
      reading = DescriptionReader.read(match_request.description, client_terms: terms)
      learned = []
      phrase = phrase_for(match_request.description, reading)
      learned << remember(phrase, { "part_number" => item["pn"] }, match_request) if phrase

      unstated = LEARNED_FIELDS.reject { |field| reading.set?(field) }
                               .to_h { |field| [ field, item[field] ] }
                               .compact_blank
      if unstated.any?
        reading.unknown_words.each do |word|
          learned << remember(word, { "fields" => unstated }, match_request)
        end
      end
      learned.compact
    end

    private

    def remember(term_text, meaning, match_request)
      record = @client.client_terms.find_or_initialize_by(term: ClientTerm.normalize_value_for(:term, term_text))
      return nil if record.persisted? && record.source == "taught"

      if record.persisted? && record.meaning == meaning
        record.times_confirmed += 1
      else
        record.meaning = meaning
        record.times_confirmed = 1
      end
      record.source = "learned"
      record.last_match_request_id = match_request.id
      record.save!
      record
    end

    # The description without its quantity: "304 ss 16ga 4x8 x25" -> "304 ss 16ga 4x8".
    def phrase_for(description, reading)
      phrase = description.to_s.dup
      quantity_text = reading.fields.dig("quantity", "text")
      phrase = phrase.sub(quantity_text, " ") if quantity_text.present?
      phrase = phrase.squish
      return nil if phrase.length < 3 || phrase.length > MAXIMUM_PHRASE_LENGTH
      return nil if reading.part_numbers.any? && phrase.casecmp?(reading.part_numbers.first)

      phrase
    end
  end
end
