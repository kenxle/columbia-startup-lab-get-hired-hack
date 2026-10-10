require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

module QuoteWorkspace
  class ApplyBuyerAnswer
    class Invalid < StandardError; end

    class AnswerMatcher < ProcessRfq::IntakeMatcher
      attr_accessor :chosen_item

      def match(**input)
        result = super
        candidates = Array(result["candidates"])
        if chosen_item
          candidate = candidates.find { |entry| entry["item_id"].to_s == chosen_item.to_s }
          unless result["status"] == "ambiguous" && candidate && Array(candidate["mismatches"]).empty?
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
    end

    def self.call(**arguments)
      new(**arguments).call
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
        payload = { "line_id" => line.line_id, "revision_id" => @revision_id }
        payload[@choice_id ? "choice_id" : "free_text"] = @choice_id || @free_text
        @stable_id, @position = line.line_id, line.position
        [snapshot, payload, BuyerContext.for(@quote)]
      end

      matcher = AnswerMatcher.new(client: nil, catalog: CatalogMatch::Catalog.new(%w[rudco metals]), service: CatalogMatch::Matcher)
      matcher.chosen_item = @chosen_item
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
      validated = ApplyResult.new(quote: @quote, result: result.merge("lines" => lines)).validated_result
      @quote.with_lock do
        line = checked_line!
        line.update!(validated[:lines].sole)
        @quote.update!(processing_revision: result["revision"], **validated[:evidence])
        @quote.invalidate_approval!
        line.enqueue_question_preview_after_commit
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
