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
      ClientTerm.where(client: @client).includes(:client).to_a.sort_by { |term| [ -term.term.length, term.term ] }
    end

    # fields: several meanings at once ({"gauge" => 16, "thickness" => 0.0625});
    # confirmed_on: the RFQ where the buyer confirmed it ("RFQ-0001").
    def teach!(term:, field: nil, value: nil, part_number: nil, fields: nil, confirmed_on: nil)
      record = @client.client_terms.find_or_initialize_by(term: ClientTerm.normalize_value_for(:term, term))
      meaning = {}
      taught = (fields || {}).to_h.stringify_keys
      taught[field.to_s] = value if field.present? && value.present?
      meaning["fields"] = taught.transform_values { |entry| entry.to_s.strip } if taught.any?
      meaning["part_number"] = part_number.to_s.upcase if part_number.present?
      meaning["confirmed_on"] = confirmed_on.to_s.strip if confirmed_on.present?
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
      codes = shorthand_codes(reading.unknown_words)
      if unstated.any? && codes.size.between?(1, MAXIMUM_CODES_PER_REQUEST)
        codes.each { |word| learned << remember(word, { "fields" => unstated }, match_request) }
      end
      learned.compact
    end

    # Buyer shorthand looks like "KB", "HB-2" or "#4b": short and code-like.
    # Ordinary words ("urgent", a company name) are never learned as meanings,
    # and a request with many unknown words teaches none of them.
    MAXIMUM_CODES_PER_REQUEST = 2
    MAXIMUM_CODE_LENGTH = 6
    COMMON_WORDS = %w[
      urgent rush asap usual same again best good new old stock price quote need want order call email
      thanks thank please hello hi team regards per for from with without and the our your this that
    ].freeze

    def shorthand_codes(words)
      words.select do |word|
        word.length <= MAXIMUM_CODE_LENGTH && word.match?(/\A[a-z0-9#\/.-]+\z/) && !COMMON_WORDS.include?(word)
      end
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
