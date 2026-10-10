# frozen_string_literal: true

require "securerandom"
require "time"

module RfqProcessing
  # Text in, the result hash out. One entry point for the quote app:
  #
  #   RfqProcessing.process(content: text, type: "email", catalog: rows)
  #
  # Steps: extract, pick the item lines, read each one (rules, then the Claude
  # parser when a key is present), match, decide readiness, flag compliance,
  # assemble. Nothing is sent anywhere.
  class Pipeline
    ITEM_HINT = /\d|\b(?:sheet|plate|bar|tube|pipe|angle|channel|stainless|steel|alum|galv|bolt|shot|grit|ingot|garnet|bead|AN\d)\b/i
    PROSE_HINT = /\A(?:hi|hello|dear|thanks|thank you|regards|best|please|we need|can you|could you|sincerely|this is|these are|it is|they are)\b/i
    HEADER = /\A(?:from|to|cc|bcc|subject|date|sent|re|fw|fwd)\s*:/i
    LIST_MARKER = /\A\s*(?:\d{1,3}[.)]|[-*•])\s+/
    SIZE_OR_QTY = /\d\s*(?:x|×|by|ga\b|gauge|"|'|in\b|ft\b|lbs?\b|pcs?\b|ea\b|each|sheets?|bags?|qty)|\bx\s*\d|\bqty\b|\d+\/\d+|\bAN\d|\b[SG]-\d{2,3}\b|\bP1020\b|\b356\b/i

    # buyer_terms: this buyer's learned or taught words, in the app's ClientTerm shape (see BuyerProfile).
    def self.process(content:, type: "email", catalog: [], matcher: nil, filename: nil, sample_data: true, context: {}, llm: nil, buyer_terms: [])
      new(catalog: catalog, matcher: matcher, llm: llm).process(content: content, type: type, filename: filename,
                                                                 sample_data: sample_data, context: context, buyer_terms: buyer_terms)
    end

    def initialize(catalog: [], matcher: nil, llm: nil)
      @matcher = matcher || CatalogMatcher.new(catalog)
      @llm = llm
    end

    def process(content:, type:, filename: nil, sample_data: true, context: {}, buyer_terms: [])
      extraction = Extractor.extract(content, type: type, filename: filename)
      item_lines = []
      body_lines = []
      extraction.lines.each do |l|
        next if HEADER.match?(l.text)

        if item_line?(l.text)
          item_lines << Extractor::Line.new(text: l.text.sub(LIST_MARKER, ""), location: l.location)
        elsif l.text.length > 12
          body_lines << l.text
        end
      end
      # Sentences in the email body ("MTRs required on all steel") carry requirements for every line.
      body_text = body_lines.join(" ")
      body_text = nil if body_text.strip.empty?
      lines = item_lines.each_with_index.map do |line, i|
        process_line(line, position: i + 1, context: context, buyer_terms: buyer_terms, extra_text: body_text)
      end
      {
        "schema_version" => RfqProcessing::SCHEMA_VERSION,
        "sample_data" => sample_data,
        "revision" => { "id" => "proc-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}",
                        "created_at" => Time.now.iso8601, "processor" => "rfq_processing #{RfqProcessing::VERSION}" },
        "source" => { "type" => extraction.source_type, "filename" => filename, "pages" => extraction.pages, "rows" => extraction.rows },
        "warnings" => extraction.warnings + (lines.empty? ? ["no item lines were found in the document"] : []),
        "lines" => lines
      }
    end

    # overrides: field => answer for this line; "catalog_item" picks one of the candidates.
    # extra_text: words that apply to the whole RFQ (a buyer's "all of it needs DFARS"), read for compliance.
    def process_line(line, position:, context: {}, buyer_terms: [], overrides: {}, extra_text: nil)
      overrides = (overrides || {}).to_h.transform_keys(&:to_s)
      chosen_item = overrides.delete("catalog_item")
      reading = RulesParser.parse(line.text, position: position, location: line.location, buyer_terms: buyer_terms, overrides: overrides)
      reading = @llm.refine(reading, line.text) if @llm
      spec = reading.fields.reject { |_, v| v.nil? }
      match = @matcher.match(line_text: line.text, spec: spec, quantity: reading.fields["quantity"], quantity_unit: reading.fields["quantity_unit"])
      match = pick_item(match, chosen_item) if chosen_item
      decision = Readiness.decide(reading, match: match, position: position)
      flag_text = [line.text, extra_text].compact.join(" ")
      compliance = defined?(Compliance) ? Compliance.flags(text: flag_text, spec: spec, context: context) : []
      ResultBuilder.build(reading: reading, decision: decision, match: match, compliance: compliance,
                          position: position, original_text: line.text, location: line.location)
    end

    # The buyer or rep chose one candidate: that item becomes the match.
    def pick_item(match, item_id)
      chosen = Array(match["candidates"]).find { |c| c["item_id"].to_s == item_id.to_s }
      return match unless chosen

      chosen = chosen.merge("score" => 1.0, "reason" => "#{chosen['reason']} Chosen by the buyer's answer.".strip)
      match.merge("status" => "exact", "best" => chosen, "candidates" => [chosen], "total_candidates" => 1)
    end

    # An item line names a size, a quantity, or a part; a sentence about the order is body text.
    def item_line?(text)
      return false if text.length < 4
      return false if PROSE_HINT.match?(text) && !SIZE_OR_QTY.match?(text)
      return false if text.split.size > 12 && text.end_with?(".") && !SIZE_OR_QTY.match?(text)

      ITEM_HINT.match?(text) && (SIZE_OR_QTY.match?(text) || text.split.size <= 8)
    end
  end

  def self.process(**args)
    Pipeline.process(**args)
  end
end
