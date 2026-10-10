require "digest"
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

module QuoteWorkspace
  class ApplyBuyerAnswer
    class Invalid < StandardError; end

    class AnswerMatcher < ProcessRfq::IntakeMatcher
      attr_accessor :chosen_item, :confirmed_answers

      def match(**input)
        result = super
        candidates = Array(result["candidates"])
        if chosen_item
          candidate = candidates.find { |entry| entry["item_id"].to_s == chosen_item.to_s }
          best = result["best"]
          chosen_best = %w[exact scored].include?(result["status"]) && best &&
            best["item_id"].to_s == chosen_item.to_s && Array(best["mismatches"]).empty? &&
            best["score"].to_f >= (result["threshold"] || RfqProcessing::CatalogMatchAdapter::THRESHOLD).to_f
          unless chosen_best || (result["status"] == "ambiguous" && candidate && Array(candidate["mismatches"]).empty?)
            raise Invalid, "This catalog choice needs rep review; its specifications are not confirmed."
          end
        end
        candidates.each do |candidate|
          price = candidate["list_price_usd_per_lb"]
          unless input[:quantity_unit].to_s == "lb" && price.is_a?(Numeric) && price.finite? && price.positive?
            candidate.delete("list_price_usd_per_lb")
            candidate.delete("list_price_source")
          end
        end
        result
      end
      private

      def call_service(text, spec = {}, quantity = nil, confirmed_terms: [])
        return super unless @service.equal?(CatalogMatch::Matcher) && Array(confirmed_answers).any?
        callable = @service.method(:call)
        supported = callable.parameters.any? { |kind, name| kind == :keyrest || ([:key, :keyreq].include?(kind) && name == :confirmed_answers) }
        return super unless supported

        arguments = { client: nil, llm: false, given: given_spec(spec, quantity: quantity),
          confirmed_answers: confirmed_answers.deep_dup }
        arguments[:catalog] = @catalog if @catalog
        arguments[:confirmed_terms] = confirmed_terms if accepts_confirmed_terms?(callable)
        @service.call(text, **arguments)
      rescue StandardError
        nil
      end

    end

    def self.call(**arguments, &block)
      new(**arguments).call(&block)
    end

    def initialize(quote:, quote_line_id:, reviewed_version:, revision_id:, choice_id: nil, free_text: nil)
      @quote, @line_id = quote, quote_line_id
      @reviewed_version, @revision_id = reviewed_version, revision_id
      @choice_id, @free_text = choice_id, free_text
    end

    def call
      validate_input!
      previous, answer, context = @quote.with_lock do
        line = checked_line!
        choices = Array(line.processing&.dig("question_choices"))
        choice = choices.find { |entry| entry.is_a?(Hash) && entry["id"] == @choice_id } if @choice_id
        raise Invalid, "Choose an option from the current question." if @choice_id && !choice
        @chosen_item = choice["value"] if choice && choice["field"] == "catalog_item"
        @confirmed_answers = confirmed_answers_for(line, choice)
        payload = { "line_id" => line.line_id, "revision_id" => @revision_id }
        payload[@choice_id ? "choice_id" : "free_text"] = @choice_id || @free_text
        @stable_id, @position = line.line_id, line.position
        [snapshot, payload, BuyerContext.for(@quote)]
      end

      matcher = AnswerMatcher.new(client: nil, catalog: CatalogMatch::Catalog.new(%w[rudco metals]), service: CatalogMatch::Matcher)
      matcher.chosen_item = @chosen_item
      matcher.confirmed_answers = @confirmed_answers
      pipeline = RfqProcessing::Pipeline.new(matcher: matcher, llm: LiveModels.parser_argument)
      result = RfqProcessing::Answers.apply(previous_result: previous, answers: [answer], pipeline: pipeline,
        buyer_terms: context.fetch(:buyer_terms))
      unless result.is_a?(Hash) && result["changed_line_ids"] == [@stable_id]
        raise Invalid, "The answer could not be applied to this line. Review the question and try again."
      end
      lines = Array(result["lines"]).select { |line| line["line_id"] == @stable_id }
      unless lines.length == 1 && lines.first["position"] == @position && result.dig("revision", "id").present? && result.dig("revision", "id") != @revision_id
        raise Invalid, "The processor returned an inconsistent answer revision. Existing lines were preserved."
      end
      if @confirmed_answers.any?
        lines.first["processing"] ||= {}
        lines.first["processing"]["confirmed_answers"] = @confirmed_answers.deep_dup
      end
      validated = ApplyResult.new(quote: @quote, result: result.merge("lines" => lines)).validated_result
      @quote.with_lock do
        line = checked_line!
        line.update!(validated[:lines].sole)
        @quote.update!(processing_revision: result["revision"], **validated[:evidence])
        @quote.invalidate_approval!
        line.enqueue_question_preview_after_commit
        yield line if block_given?
        line
      end
    rescue ActiveRecord::RecordInvalid, ApplyResult::InvalidResult, ProcessRfq::InputError => error
      raise Invalid, error.message
    end

    private

    def validate_input!
      unless (@line_id.is_a?(String) || @line_id.is_a?(Integer)) && @line_id.to_s.match?(/\A[1-9]\d{0,18}\z/)
        raise Invalid, "Choose a held line from this RFQ."
      end
      unless @reviewed_version.is_a?(String) && @reviewed_version.present? && @reviewed_version.length <= 200 &&
          @revision_id.is_a?(String) && @revision_id.present? && @revision_id.length <= 200
        raise Quote::StaleReview, "Review the current question before applying an answer."
      end
      [@choice_id, @free_text].each do |value|
        raise Invalid, "Answers must be text." unless value.nil? || value.is_a?(String)
      end
      @choice_id = @choice_id&.strip.presence
      @free_text = @free_text&.strip.presence
      unless [@choice_id, @free_text].compact.length == 1 && @choice_id.to_s.length <= 200 && @free_text.to_s.length <= 2000
        raise Invalid, "Choose one option or enter an answer of at most 2000 characters."
      end
    end

    def checked_line!
      @quote.quote_lines.reload
      unless @quote.review_revision == @reviewed_version && @quote.processing_revision&.dig("id") == @revision_id
        raise Quote::StaleReview, "This RFQ changed. Review its latest question before applying an answer."
      end
      raise Invalid, "Wait for current RFQ processing to finish." if @quote.processing_runs.where(status: ProcessingRun::ACTIVE_STATUSES).exists?
      line = @quote.quote_lines.find(@line_id)
      raise Invalid, "Only held lines can receive an answer." if line.state == "ready"
      raise Invalid, "This line has rep edits. Review them before reprocessing; they have been preserved." if Array(line.edited_fields).any?
      unless line.line_id.present? && @quote.quote_lines.to_a.count { |entry| entry.line_id == line.line_id } == 1
        raise Invalid, "This line needs a stable processing identity before an answer can be applied."
      end
      line
    end

    # Only a persisted, current multiple-choice answer grants numeric authority.
    # Free text and ordinary normalized specs never create this attestation.
    def confirmed_answers_for(line, choice)
      digest = Digest::SHA256.hexdigest(line.original_text.to_s)
      prior = Array(line.processing&.dig("confirmed_answers")).select do |entry|
        next false unless entry.is_a?(Hash) && entry["field"] == "thickness" && valid_thickness?(entry["value"])
        provenance = entry["provenance"]
        next false unless provenance.is_a?(Hash) && provenance["method"] == "explicit_buyer_choice" &&
          provenance["quote_id"] == @quote.id && provenance["quote_line_id"] == line.id &&
          provenance["line_id"] == line.line_id && provenance["quote_reference"] == @quote.reference &&
          provenance["source_sha256"] == digest && provenance["choice_id"].is_a?(String) && provenance["choice_id"].present? &&
          provenance["revision_id"].is_a?(String) && provenance["revision_id"].present?
        next false unless line.processing.dig("answered", "choice_id").to_s.split(",").map(&:strip).include?(provenance["choice_id"])
        evidence = line.evidence&.dig("thickness")
        evidence.is_a?(Hash) && evidence["location"] == "buyer answer" &&
          evidence["explanation"].to_s.start_with?("answered by the buyer: ") &&
          line.spec["thickness"].to_s.to_d == entry["value"].to_s.to_d &&
          entry["source_text"] == original_thickness_phrase(line)
      end.map(&:deep_dup)
      return prior unless choice && choice["field"] == "thickness_in" && valid_thickness?(choice["value"])

      phrase = original_thickness_phrase(line)
      return prior unless phrase.present? && phrase.length <= 200
      [{ "field" => "thickness", "value" => choice["value"], "source_text" => phrase,
        "provenance" => { "method" => "explicit_buyer_choice", "quote_id" => @quote.id,
          "quote_line_id" => line.id, "line_id" => line.line_id, "quote_reference" => @quote.reference,
          "revision_id" => @revision_id, "choice_id" => choice["id"], "source_sha256" => digest } }]
    end

    def valid_thickness?(value)
      number = Float(value, exception: false) if value.is_a?(Numeric) || value.is_a?(String)
      number && number.finite? && number.positive? && number <= 1000
    end

    def original_thickness_phrase(line)
      reading = CatalogMatch::DescriptionReader.read(line.original_text)
      reading.fields.dig("thickness", "text")
    end

    def snapshot
      {
        "schema_version" => 1, "sample_data" => @quote.sample_data?, "revision" => @quote.processing_revision.deep_dup,
        "source" => @quote.processing_source.deep_dup, "warnings" => @quote.processing_warnings.deep_dup,
        "lines" => @quote.quote_lines.map do |line|
          attributes = line.attributes.slice(*ApplyResult::LINE_KEYS).deep_dup
          %w[quantity unit_price].each { |key| attributes[key] = attributes[key]&.to_s("F") }
          attributes
        end
      }
    end
  end
end
