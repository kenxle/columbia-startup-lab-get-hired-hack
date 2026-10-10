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
    ITEM_HINT = /\d|\b(?:sheet|plate|bar|tube|pipe|angle|channel|stainless|steel|alum|galv|bolt|AN\d)\b/i
    PROSE_HINT = /\A(?:hi|hello|dear|thanks|thank you|regards|best|please|we need|can you|could you|sincerely)\b/i

    def self.process(content:, type: "email", catalog: [], matcher: nil, filename: nil, sample_data: true, context: {}, llm: nil)
      new(catalog: catalog, matcher: matcher, llm: llm).process(content: content, type: type, filename: filename,
                                                                 sample_data: sample_data, context: context)
    end

    def initialize(catalog: [], matcher: nil, llm: nil)
      @matcher = matcher || CatalogMatcher.new(catalog)
      @llm = llm
    end

    def process(content:, type:, filename: nil, sample_data: true, context: {})
      extraction = Extractor.extract(content, type: type, filename: filename)
      item_lines = extraction.lines.select { |l| item_line?(l.text) }
      lines = item_lines.each_with_index.map { |line, i| process_line(line, position: i + 1, context: context) }
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

    def process_line(line, position:, context: {})
      reading = RulesParser.parse(line.text, position: position, location: line.location)
      reading = @llm.refine(reading, line.text) if @llm
      spec = reading.fields.reject { |_, v| v.nil? }
      match = @matcher.match(line_text: line.text, spec: spec, quantity: reading.fields["quantity"], quantity_unit: reading.fields["quantity_unit"])
      decision = Readiness.decide(reading, match: match, position: position)
      compliance = defined?(Compliance) ? Compliance.flags(text: line.text, spec: spec, context: context) : []
      ResultBuilder.build(reading: reading, decision: decision, match: match, compliance: compliance,
                          position: position, original_text: line.text, location: line.location)
    end

    def item_line?(text)
      return false if text.length < 4
      return false if PROSE_HINT.match?(text) && !text.match?(/\d/)

      ITEM_HINT.match?(text)
    end
  end

  def self.process(**args)
    Pipeline.process(**args)
  end
end
