# frozen_string_literal: true

module RfqProcessing
  # Workflow step 9, the parsing side: what this buyer's words mean.
  #
  # One buyer writes "20 gate steel", another "20G steel". After the rep confirms
  # a reading once, the next RFQ from that buyer reads it right, and the line
  # says so: "Northline (learned from 1 approved request): 20G means gauge 20".
  # When the term carries the RFQ number it was confirmed on, the line names that
  # RFQ instead: "Read as thickness 0.0625 in, as you confirmed on RFQ-0001".
  #
  # Terms arrive in the app's ClientTerm shape (Tisch's table), string keys:
  #   { "term" => "20g", "meaning" => { "fields" => { "gauge" => 20 } }, "source" => "taught",
  #     "client_name" => "Northline", "times_confirmed" => 1, "confirmed_on" => "RFQ-0001" }
  # or with "meaning" => { "part_number" => "AN3-13A" }. "confirmed_on" is optional.
  module BuyerProfile
    # ClientTerm field => parser field. Tisch's six teachable fields, plus the three
    # the parser needs for shorthand like "20G" or "sold by the bag".
    FIELD_MAP = {
      "material" => "material", "grade" => "grade", "temper" => "temper", "form" => "form", "finish" => "finish",
      "standard" => "standard", "gauge" => "gauge", "thickness" => "thickness_in", "thickness_in" => "thickness_in",
      "quantity_unit" => "quantity_unit", "part_number" => "part_number"
    }.freeze

    Hit = Struct.new(:term, :match, :fields, :explanation, :describe, :how, :confirmed_on, keyword_init: true)

    # Every term of this buyer that appears in the text, earliest first.
    def self.apply(terms, text)
      Array(terms).filter_map do |raw|
        term = stringify(raw)
        phrase = term["term"].to_s.strip
        next if phrase.empty?

        match = pattern_for(phrase).match(text.to_s)
        next unless match

        fields = fields_for(term)
        next if fields.empty?

        how = how_for(term)
        describe = fields.map { |f, v| "#{f.sub('_in', '')} #{v}" }.join(", ")
        confirmed_on = confirmed_on_for(term)
        Hit.new(term: phrase, match: match, fields: fields, describe: describe, how: how, confirmed_on: confirmed_on,
                explanation: explanation_for(term, match, fields, describe, how, confirmed_on))
      end.sort_by { |hit| hit.match.begin(0) }
    end

    # A rep edit becomes a term the app can save as "learned". Returns nil when the
    # evidence words are too generic to teach (a bare number, a single letter).
    # confirmed_on is the RFQ number the rep confirmed the reading on, when known.
    def self.learn(evidence_text:, field:, value:, client_name: nil, confirmed_on: nil)
      phrase = evidence_text.to_s.strip.squeeze(" ")
      return nil if phrase.length < 2 || phrase.match?(/\A\d+(?:\.\d+)?\z/)

      key = FIELD_MAP.key(field.to_s) || field.to_s
      meaning = key == "part_number" ? { "part_number" => value.to_s } : { "fields" => { key => value } }
      term = { "term" => phrase.downcase, "meaning" => meaning, "source" => "learned", "client_name" => client_name, "times_confirmed" => 1 }
      term["confirmed_on"] = confirmed_on unless confirmed_on.nil?
      term
    end

    # The words the line shows. With the RFQ the reading was confirmed on, the line
    # names that RFQ. Without it, who taught the term and what it means.
    def self.explanation_for(term, match, fields, describe, how, confirmed_on)
      return "#{term['client_name'] || 'this buyer'} (#{how}): \"#{match[0]}\" means #{describe}" unless confirmed_on

      who = taught?(term) ? "the rep taught" : "you confirmed"
      "Read as #{read_as(fields)}, as #{who} on #{confirmed_on}"
    end

    # "thickness 0.0625 in", "gauge 16": a thickness carries its unit; other fields read as in describe.
    def self.read_as(fields)
      fields.map { |f, v| f == "thickness_in" ? "thickness #{v} in" : "#{f.sub('_in', '')} #{v}" }.join(", ")
    end

    def self.confirmed_on_for(term)
      value = term["confirmed_on"].to_s.strip
      value.empty? ? nil : value
    end

    def self.pattern_for(phrase)
      escaped = Regexp.escape(phrase.squeeze(" ")).gsub('\ ', '\s+')
      lead = phrase.match?(/\A[[:alnum:]]/) ? '(?<![[:alnum:]])' : ""
      trail = phrase.match?(/[[:alnum:]]\z/) ? '(?![[:alnum:]])' : ""
      Regexp.new("#{lead}#{escaped}#{trail}", Regexp::IGNORECASE)
    end

    def self.fields_for(term)
      meaning = term["meaning"].is_a?(Hash) ? term["meaning"] : {}
      fields = {}
      (meaning["fields"] || {}).each do |k, v|
        parser_field = FIELD_MAP[k.to_s]
        next unless parser_field && !v.nil?

        fields[parser_field] = parser_field == "gauge" ? v.to_i : (parser_field == "thickness_in" ? v.to_f : v.to_s)
      end
      fields["part_number"] = meaning["part_number"].to_s if meaning["part_number"].to_s.strip != ""
      fields
    end

    def self.taught?(term)
      term["source"].to_s == "taught"
    end

    def self.how_for(term)
      if taught?(term)
        "taught by the rep"
      else
        n = term["times_confirmed"].to_i
        n = 1 if n < 1
        "learned from #{n} approved #{n == 1 ? 'request' : 'requests'}"
      end
    end

    def self.stringify(hash)
      h = hash.respond_to?(:to_h) ? hash.to_h : {}
      h = h.transform_keys(&:to_s)
      h["meaning"] = h["meaning"].to_h.transform_keys(&:to_s) if h["meaning"].respond_to?(:to_h)
      h["meaning"]["fields"] = h["meaning"]["fields"].to_h.transform_keys(&:to_s) if h["meaning"].is_a?(Hash) && h["meaning"]["fields"].respond_to?(:to_h)
      h
    end
  end
end
