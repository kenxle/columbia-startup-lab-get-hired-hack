require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

module QuoteWorkspace
  # Whole-RFQ processing only. Rep edits require a future merge contract.
  class ProcessRfq
    class InputError < StandardError; end
    ACTIVE_RUN_TIMEOUT = 5.minutes
    CONFLICT_MESSAGE = "This RFQ has rep edits. Full reprocessing is blocked to preserve those edits. Processing only changed lines is not connected.".freeze
    STALE_MESSAGE = "The RFQ changed after processing was requested. These results were not applied.".freeze

    # RudCo observations are per pound. A bag, kg, or each quantity is not a
    # pound quantity; leaving its price absent invokes the processor's hold.
    class IntakeMatcher < RfqProcessing::CatalogMatchAdapter
      def match(**input)
        if explicit_catalog_part_number?(input[:line_text])
          raise InputError, "Explicit catalog part numbers require rep review because all requested specifications cannot yet be verified. Review the original request and catalog item before quoting; existing quote lines were preserved."
        end
        result = super
        if result["reason"] == "matcher unavailable"
          raise InputError, "Catalog matching is temporarily unavailable. Existing quote lines were preserved. Try again."
        end
        best = result["best"]
        price = best && best["list_price_usd_per_lb"]
        if best && (input[:quantity_unit].to_s != "lb" || !price.is_a?(Numeric) || !price.finite? || !price.positive?)
          result["best"] = best.except("list_price_usd_per_lb", "list_price_source")
        end
        result
      end

      private

      # The catalog matcher has its own optional provider, independent of the
      # processing pipeline's llm flag. Keep catalog reads local until their
      # model-filled fields and evidence can be shown in the review contract.
      def call_service(text, spec = {}, quantity = nil)
        unless @service.equal?(CatalogMatch::Matcher)
          return super(text) if method(:call_service).super_method.arity == 1
          return super(text, spec, quantity)
        end

        arguments = { client: nil, llm: false }
        arguments[:catalog] = @catalog if @catalog
        arguments[:given] = given_spec(spec, quantity: quantity) if respond_to?(:given_spec, true)
        @service.call(text, **arguments)
      rescue StandardError
        nil # match turns unavailable matching into the existing safe failure.
      end

      # The upstream PN shortcut does not verify other stated attributes.
      # Fail closed until shared matching checks the complete specification.
      def explicit_catalog_part_number?(text)
        (@catalog || CatalogMatch::Catalog.default).part_numbers.any? do |part_number|
          text.to_s.match?(/(?<![A-Z0-9])#{Regexp.escape(part_number)}(?![A-Z0-9])/i)
        end
      end
    end

    def self.enqueue(quote:, expected_revision:)
      new(quote).enqueue(expected_revision)
    end

    def self.perform(run_id)
      run = ProcessingRun.find_by(id: run_id)
      return unless run

      new(run.quote).perform(run)
    end

    def initialize(quote)
      @quote = quote
    end

    def enqueue(expected_revision)
      dispatch = false
      run = @quote.with_lock do
        raise Quote::StaleReview, "Review the current RFQ before processing." if expected_revision.blank?

        active = runs.where(status: ProcessingRun::ACTIVE_STATUSES).order(id: :desc).first
        matches_active = active && active.source_revision == @quote.review_revision &&
            [active.requested_revision, active.source_revision].include?(expected_revision)
        unless expected_revision == @quote.review_revision || matches_active
          raise Quote::StaleReview, "This RFQ changed. Review the current version before processing."
        end
        if active && expired?(active)
          active.update!(status: "stale", finished_at: Time.current,
            error_message: "This processing run timed out. An explicit retry replaced it; late results will not be applied.")
        elsif matches_active
          next active
        end

        @quote.quote_lines.reload
        if rep_edits?
          next runs.create!(status: "conflict", requested_revision: expected_revision,
            source_revision: @quote.review_revision, queued_at: Time.current, finished_at: Time.current,
            error_message: CONFLICT_MESSAGE)
        end

        @quote.invalidate_approval!
        dispatch = true
        content, type, filename = capture_source
        runs.create!(requested_revision: expected_revision, source_revision: @quote.review_revision,
          source_content: content, source_type: type, source_filename: filename, queued_at: Time.current)
      end
      if dispatch
        begin
          job = ProcessRfqJob.perform_later(run.id)
          finish_failure(run, "Processing could not be queued. Try again.") unless job
        rescue StandardError
          finish_failure(run, "Processing could not be queued. Try again.")
        end
      end
      run.reload
    end

    def perform(run)
      input = @quote.with_lock do
        run.reload
        next unless run.status == "queued"
        next unless eligible?(run)

        run.update!(status: "running", started_at: Time.current)
        {content: run.source_content.to_s.dup.freeze, type: run.source_type, filename: run.source_filename,
          buyer_context: BuyerContext.for(@quote)}
      end
      return run.reload unless input

      buyer_context = input.delete(:buyer_context)
      validate_source!(input)
      # Aviation currently loses quote-readiness holds in the shared adapter.
      # Keep it out of intake until the processing/matching owners resolve that.
      catalog = CatalogMatch::Catalog.new(%w[rudco metals])
      # Legacy matcher memory learns from unconfirmed near matches. Until
      # that provenance is repaired, only vetted parser terms may be used.
      matcher = IntakeMatcher.new(client: nil, catalog: catalog, service: CatalogMatch::Matcher)
      result = RfqProcessing.process(**input, matcher: matcher,
        buyer_terms: buyer_context.fetch(:buyer_terms), sample_data: true, context: {}, llm: LiveModels.parser_argument)
      @quote.with_lock do
        run.reload
        next unless run.status == "running" && eligible?(run)

        warnings = bounded_warnings(result)
        if result.is_a?(Hash) && result["lines"].is_a?(Array) && result["lines"].empty?
          @quote.assign_processing_evidence(source: result["source"], warnings: result["warnings"])
          @quote.save!
          run.update!(status: "failed", error_message: warnings.join(" ").presence&.first(1_000) ||
            "No item lines were found. Check the source and try again.", warnings: warnings, finished_at: Time.current)
          next
        end
        # ApplyResult's own lock joins this transaction. A savepoint ensures
        # its model-validation rescue cannot retain partially replaced rows.
        @quote.class.transaction(requires_new: true) do
          ApplyResult.call(quote: @quote, result: result, preview_questions: true)
        end
        run.update!(status: "succeeded", warnings: warnings, finished_at: Time.current)
      end
      run.reload
    rescue InputError => error
      finish_failure(run, error.message)
    rescue LoadError
      finish_failure(run, "A required processing dependency is unavailable. Ask the workspace maintainer to complete setup, then retry.")
    rescue ApplyResult::InvalidResult
      finish_failure(run, "The processing result could not be saved. Existing quote lines were preserved. Check the RFQ and try again.")
    rescue StandardError
      finish_failure(run, "Processing failed. Existing quote lines were preserved. Try again or review the source.")
    end

    private

    def runs
      ProcessingRun.where(quote_id: @quote.id)
    end

    def expired?(run)
      active_since = run.status == "running" ? run.started_at || run.queued_at : run.queued_at
      active_since <= Time.current - ACTIVE_RUN_TIMEOUT
    end

    def rep_edits?
      @quote.quote_lines.any? { |line| Array(line.edited_fields).any? }
    end

    def eligible?(run)
      @quote.quote_lines.reload
      if rep_edits?
        run.update!(status: "conflict", error_message: CONFLICT_MESSAGE, finished_at: Time.current)
        false
      elsif run.source_revision != @quote.review_revision || runs.where("id > ?", run.id).exists?
        run.update!(status: "stale", error_message: STALE_MESSAGE, finished_at: Time.current)
        false
      else
        true
      end
    end

    def finish_failure(run, message)
      @quote.reload
      @quote.with_lock do
        run.reload
        if run.active? && eligible?(run)
          run.update!(status: "failed", error_message: message.to_s.first(1_000), finished_at: Time.current)
        end
      end
      run.reload
    end

    def capture_source
      if @quote.source_bytes.present?
        filename = @quote.original_filename
        type = {".pdf" => "pdf", ".csv" => "csv", ".txt" => "email"}.fetch(File.extname(filename.to_s).downcase, "unsupported")
        [@quote.source_bytes.dup, type, filename]
      else
        [@quote.source_text.to_s.dup, "email", nil]
      end
    end

    def validate_source!(input)
      extension = File.extname(input[:filename].to_s).downcase
      raise InputError, "Save this Excel file as CSV and upload it again." if %w[.xls .xlsx].include?(extension)
      raise InputError, "Raw email files are not connected. Paste the email body or upload its PDF or CSV attachment." if extension == ".eml"
      raise InputError, "This source type is not supported. Use pasted text, PDF, or CSV." if input[:type] == "unsupported"
      raise InputError, "The source is empty." if input[:content].empty?
      raise InputError, "The source is larger than 10 MB." if input[:content].bytesize > Quote::MAXIMUM_SOURCE_BYTES
      if input[:type] != "pdf"
        input[:content] = input[:content].dup.force_encoding(Encoding::UTF_8)
        raise InputError, "The source is not valid UTF-8 text. Save it as UTF-8 and try again." unless input[:content].valid_encoding?
      end
    end

    def bounded_warnings(result)
      return [] unless result.is_a?(Hash) && result["warnings"].is_a?(Array)

      result["warnings"].first(20).filter_map { |warning| warning.first(500) if warning.is_a?(String) }
    end
  end
end
