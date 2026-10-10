# frozen_string_literal: true

require "securerandom"
require "time"

module RfqProcessing
  # A buyer's answers, applied (workflow decision W3). Only the answered lines
  # rerun; an answer that covers the whole RFQ reruns every line (guard 1); the
  # untouched lines are copied as they were; and the new result names the run
  # it came from plus the lines that changed (guard 4). Keeping a rep's edits
  # and clearing approval are the app's job (guards 2 and 3).
  #
  #   RfqProcessing::Answers.apply(previous_result: result, answers: [...], pipeline: pipeline)
  #
  # answers: Array of Hash with string keys, each one of
  #   { "line_id" => id, "choice_id" => choice id }   a one-click choice from processing.question_choices
  #   { "line_id" => id, "free_text" => words }       typed words for one line
  #   { "scope" => "rfq", "free_text" => words }      words that apply to the whole RFQ
  # Any answer may carry "revision_id", the revision the buyer answered. A stale
  # one is still applied and noted in the warnings.
  #
  # Several answers for one line in one batch are applied together in a single
  # rerun. The line's processing.answered then lists every choice id, comma
  # separated, and the free texts joined with a semicolon.
  module Answers
    CHARS = /, chars \d+-\d+\z/
    BUYER_LOCATION = "buyer answer"

    def self.apply(previous_result:, answers:, pipeline:, buyer_terms: [], context: {})
      previous = previous_result.to_h
      previous_revision = previous.dig("revision", "id")
      lines = Array(previous["lines"])
      by_id = lines.each_with_object({}) { |line, h| h[line["line_id"].to_s] = line }
      plans = Hash.new { |h, id| h[id] = { "overrides" => {}, "choice_ids" => [], "free_texts" => [], "rfq_texts" => [] } }
      warnings = []

      Array(answers).each do |raw|
        answer = raw.to_h.transform_keys(&:to_s)
        if answer["scope"].to_s == "rfq"
          plan_rfq(answer, lines, plans, previous_revision, warnings)
        else
          plan_line(answer, by_id, plans, previous_revision, warnings)
        end
      end

      rebuilt = {}
      lines.each_with_index do |line, i|
        id = line["line_id"].to_s
        next unless plans.key?(id) && !plan_empty?(plans[id])

        rebuilt[id] = rerun(line, plans[id], position: line["position"] || i + 1, pipeline: pipeline, buyer_terms: buyer_terms,
                                               context: context, previous_revision: previous_revision, warnings: warnings)
      end

      now = Time.now
      {
        "schema_version" => previous["schema_version"] || RfqProcessing::SCHEMA_VERSION,
        "sample_data" => previous.fetch("sample_data", true),
        "revision" => { "id" => "proc-#{now.getutc.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}",
                        "created_at" => now.iso8601, "processor" => "rfq_processing #{RfqProcessing::VERSION} (answers)" },
        "source" => deep_copy(previous["source"]),
        "warnings" => Array(previous["warnings"]) + warnings,
        "lines" => lines.map { |line| rebuilt[line["line_id"].to_s] || deep_copy(line) },
        "previous_revision" => previous_revision,
        "changed_line_ids" => lines.map { |line| line["line_id"].to_s }.select { |id| rebuilt.key?(id) }
      }
    end

    # ---- which lines rerun, and with what --------------------------------

    def self.plan_rfq(answer, lines, plans, previous_revision, warnings)
      text = answer["free_text"].to_s.strip
      if text.empty?
        warnings << "a whole-RFQ answer has no text; it was skipped"
        return
      end
      if lines.empty?
        warnings << "a whole-RFQ answer was given but the result has no lines to rerun"
        return
      end

      note_stale(answer, "whole RFQ", previous_revision, warnings)
      lines.each { |line| plans[line["line_id"].to_s]["rfq_texts"] << text }
    end

    def self.plan_line(answer, by_id, plans, previous_revision, warnings)
      id = answer["line_id"].to_s
      line = by_id[id]
      unless line
        warnings << "unknown line_id #{id.inspect}; the answer was skipped"
        return
      end

      note_stale(answer, "line #{id}", previous_revision, warnings)
      if answer["choice_id"]
        plan_choice(answer["choice_id"].to_s, line, plans[id], previous_revision, warnings)
      elsif !answer["free_text"].to_s.strip.empty?
        plans[id]["free_texts"] << answer["free_text"].to_s.strip
      else
        warnings << "line #{id}: the answer has neither a choice_id nor free_text; it was skipped"
      end
    end

    def self.plan_choice(choice_id, line, plan, previous_revision, warnings)
      id = line["line_id"].to_s
      choice = Array(line.dig("processing", "question_choices")).find { |c| c.is_a?(Hash) && c["id"].to_s == choice_id }
      field = choice && choice["field"].to_s
      if choice.nil?
        warnings << "line #{id}: unknown choice_id #{choice_id.inspect}; the answer was skipped"
      elsif field.empty?
        warnings << "line #{id}: choice #{choice_id} names no field; the answer was skipped"
      elsif field == "catalog_item"
        plan["overrides"]["catalog_item"] = choice["value"]
        plan["choice_ids"] << choice["id"]
      else
        plan["overrides"][field] = {
          "value" => choice["value"], "text" => choice["label"],
          "explanation" => "answered by the buyer: #{choice['label']} (choice #{choice['id']}, revision #{previous_revision})"
        }
        plan["choice_ids"] << choice["id"]
      end
    end

    def self.note_stale(answer, what, previous_revision, warnings)
      given = answer["revision_id"].to_s
      return if given.empty? || given == previous_revision.to_s

      warnings << "#{what}: the answer was given on revision #{given}; it was applied to revision #{previous_revision}"
    end

    def self.plan_empty?(plan)
      plan["overrides"].empty? && plan["choice_ids"].empty? && plan["free_texts"].empty? && plan["rfq_texts"].empty?
    end

    # ---- one line, rerun --------------------------------------------------

    def self.rerun(line, plan, position:, pipeline:, buyer_terms:, context:, previous_revision:, warnings:)
      original = line["original_text"].to_s
      free_text = plan["free_texts"].uniq.join("; ")
      rfq_text = plan["rfq_texts"].uniq.join(" ")
      text = free_text.empty? ? original : "#{original} (buyer: #{free_text})"
      source = Extractor::Line.new(text: text, location: location_of(line, position))

      rebuilt = pipeline.process_line(source, position: position, context: context, buyer_terms: buyer_terms,
                                              overrides: plan["overrides"], extra_text: rfq_text.empty? ? nil : rfq_text)
      rebuilt["processing"] ||= {}

      unless free_text.empty?
        restore_identity(rebuilt, line, original)
        rebuilt["processing"]["answered_with"] = free_text
        if rebuilt["clarification_question"] && rebuilt["clarification_question"] == line["clarification_question"]
          warnings << "line #{line['line_id']}: the buyer's answer did not settle the question; rep review needed"
        end
      end

      rebuilt["processing"]["answered"] = {
        "choice_id" => plan["choice_ids"].empty? ? nil : plan["choice_ids"].join(", "),
        "free_text" => free_text.empty? ? nil : free_text,
        "rfq_text" => rfq_text.empty? ? nil : rfq_text,
        "previous_revision" => previous_revision
      }
      rebuilt
    end

    # The base location the extractor gave this line ("line 3", "row 4"), recovered
    # from the stored evidence, which carries it with a ", chars a-b" suffix.
    def self.location_of(line, position)
      found = Array(line["evidence"]&.values).filter_map { |ev| ev["location"].to_s if ev.is_a?(Hash) }
                                             .find { |loc| !loc.empty? && loc != BUYER_LOCATION }
      found ? found.sub(CHARS, "") : "line #{position}"
    end

    # A free-text rerun parsed the RFQ words plus the buyer's words, so the
    # pipeline derived a different line_id. The line keeps its identity: the old
    # line_id, its choice ids, and the RFQ words verbatim. Evidence read from
    # the buyer's words (past the end of the RFQ text) is located there.
    def self.restore_identity(rebuilt, line, original)
      previous_id = line["line_id"].to_s
      new_id = rebuilt["line_id"].to_s
      rebuilt["line_id"] = previous_id
      rebuilt["original_text"] = line["original_text"]
      Array(rebuilt.dig("processing", "question_choices")).each { |c| c["id"] = c["id"].to_s.sub(new_id, previous_id) }
      Array(rebuilt["evidence"]&.values).each do |ev|
        next unless ev.is_a?(Hash)

        start = ev["location"].to_s[/, chars (\d+)-\d+\z/, 1]
        ev["location"] = BUYER_LOCATION if start && start.to_i > original.length
      end
    end

    def self.deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end
