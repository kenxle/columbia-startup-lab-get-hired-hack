# frozen_string_literal: true

require "securerandom"
require "time"
require_relative "item_lines"

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
    PROSE_HINT = /\A(?:hi|hello|dear|thanks|thank you|regards|best|please|we need|can you|could you|sincerely|this is|these are|it is|they are|same)\b/i
    HEADER = /\A(?:from|to|cc|bcc|subject|date|sent|re|fw|fwd|attachments?|ship to)\s*:/i
    LIST_MARKER = /\A\s*(?:\d{1,3}[.)]|[-*•])\s+/
    SIZE_OR_QTY = /\d\s*(?:x|×|by|ga\b|gauge|"|'|in\b|ft\b|lbs?\b|pcs?\b|ea\b|each|sheets?|bags?|qty)|\bx\s*\d|\bqty\b|\d+\/\d+|\bAN\d|\b[SG]-\d{2,3}\b|\bP1020\b|\b356\b/i

    # buyer_terms: this buyer's learned or taught words, in the app's ClientTerm shape (see BuyerProfile).
    def self.process(content:, type: "email", catalog: [], matcher: nil, filename: nil, sample_data: false, context: {}, llm: nil, buyer_terms: [])
      new(catalog: catalog, matcher: matcher, llm: llm).process(content: content, type: type, filename: filename,
                                                                 sample_data: sample_data, context: context, buyer_terms: buyer_terms)
    end

    # llm: pass false to force rules only; nil picks the Claude step up from the environment when a key exists.
    def initialize(catalog: [], matcher: nil, llm: nil)
      @matcher = matcher || CatalogMatcher.new(catalog)
      @llm = llm.nil? ? (defined?(LlmParser) ? LlmParser.from_env : nil) : (llm || nil)
    end

    def process(content:, type:, filename: nil, sample_data: false, context: {}, buyer_terms: [])
      extraction = Extractor.extract(content, type: type, filename: filename)
      item_lines = []
      body_lines = []
      if extraction.source_type == "pdf"
        item_lines = ItemLines.pdf(extraction)
      else
        extraction.lines.each do |l|
          next if HEADER.match?(l.text)

          if item_line?(l.text)
            item_lines << Extractor::Line.new(text: l.text.sub(LIST_MARKER, ""), location: l.location)
          elsif l.text.length > 12
            body_lines << l.text
          end
        end
      end
      # Sentences in the email body ("MTRs required on all steel") carry requirements for every line.
      body_text = extraction.source_type == "pdf" ? ItemLines.body_text(extraction) : body_lines.join("\n")
      body_text = nil if body_text.strip.empty?
      lines = item_lines.each_with_index.map do |line, i|
        process_line(line, position: i + 1, context: context, buyer_terms: buyer_terms, extra_text: body_text)
      end
      {
        "schema_version" => RfqProcessing::SCHEMA_VERSION,
        "sample_data" => sample_data,
        "revision" => { "id" => "proc-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}",
                        "created_at" => Time.now.iso8601, "processor" => "rfq_processing #{RfqProcessing::VERSION}",
                        "llm" => llm_description },
        "source" => { "type" => extraction.source_type, "filename" => filename, "pages" => extraction.pages, "rows" => extraction.rows },
        "warnings" => extraction.warnings + (lines.empty? ? ["no item lines were found in the document"] : []),
        "lines" => lines
      }
    end

    # What the Claude step says about itself, {"provider" => ..., "model" => ...} with string keys, for
    # revision.llm. Nil when the run is rules only or the step cannot describe itself.
    def llm_description
      @llm.respond_to?(:describe) ? @llm.describe : nil
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
      match, rejected = pick_item(match, chosen_item) if chosen_item
      decision = Readiness.decide(reading, match: match, position: position)
      # Recorded after the decision, so the line keeps its state; Answers.apply turns it into a warning.
      reading.conflicts << rejected if rejected
      compliance = defined?(Compliance) ? Compliance.flags(text: line.text, body_text: extra_text, spec: spec, context: context) : []
      result = ResultBuilder.build(reading: reading, decision: decision, match: match, compliance: compliance,
                          position: position, original_text: line.text, location: line.location)
      requirement_body = Compliance.requirement_text(extra_text)
      result["processing"]["rfq_body"] = requirement_body unless requirement_body.empty?
      result
    end

    REJECTED_PICK = "chosen_item_rejected"

    # The buyer or rep chose one candidate: that item becomes the match. Only a candidate of an ambiguous or
    # scored match, at or above the threshold, can be chosen; a no match line's closest items (which sit in
    # the same candidates key) never can. Returns [match, conflict or nil].
    def pick_item(match, item_id)
      return [match, nil] if %w[exact scored].include?(match["status"]) &&
                            match.dig("best", "item_id").to_s == item_id.to_s &&
                            match.dig("best", "score").to_f >= (match["threshold"] || CatalogMatchAdapter::THRESHOLD).to_f &&
                            Array(match.dig("best", "mismatches")).empty?

      threshold = (match["threshold"] || CatalogMatchAdapter::THRESHOLD).to_f
      chosen = Array(match["candidates"]).find { |c| c["item_id"].to_s == item_id.to_s } if %w[ambiguous scored].include?(match["status"].to_s)
      chosen = nil if chosen && (chosen["score"].to_f < threshold || Array(chosen["mismatches"]).any?)
      unless chosen
        return [match, { "code" => REJECTED_PICK, "fields" => [],
                         "message" => "the chosen item #{item_id} was not a catalog candidate for this line; the line keeps its state" }]
      end

      chosen = chosen.merge("score" => 1.0, "reason" => "#{chosen['reason']} Chosen by the buyer's answer.".strip)
      [match.merge("status" => "exact", "best" => chosen, "candidates" => [chosen], "total_candidates" => 1), nil]
    end

    # An item line names a size, a quantity, or a part; a sentence about the order is body text.
    def item_line?(text)
      return false if text.length < 4
      return false if Compliance::FAMILY_SCOPE.match?(text) && !Compliance.requirement_text(text).empty? && !SIZE_OR_QTY.match?(text)
      return false if PROSE_HINT.match?(text) && !SIZE_OR_QTY.match?(text)
      return false if text.split.size > 12 && text.end_with?(".") && !SIZE_OR_QTY.match?(text)

      ITEM_HINT.match?(text) && (SIZE_OR_QTY.match?(text) || text.split.size <= 8)
    end
  end

  def self.process(**args)
    Pipeline.process(**args)
  end
end
