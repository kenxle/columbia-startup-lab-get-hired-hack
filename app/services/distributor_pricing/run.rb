require "digest"
require Rails.root.join("tools/distributor_pricing/lib/distributor_pricing/intake").to_s

module DistributorPricing
  class Run
    class InputError < StandardError; end
    ACTIVE_TIMEOUT = 10.minutes
    STALE_MESSAGE = "The RFQ changed after this price check started. Run a new check for the current request.".freeze

    def self.source_digest(quote)
      source_digest_values(quote.source_text, quote.original_filename, quote.source_bytes)
    end

    def self.source_digest_values(text, filename, bytes)
      Digest::SHA256.hexdigest(JSON.generate([text, filename]).b + "\0".b + bytes.to_s.b)
    end

    # Approval timestamps are not pricing inputs. Other saved line/header
    # changes still invalidate the displayed result.
    def self.input_fingerprint(quote)
      rows = quote.quote_lines.order(:id).map { |line| line.attributes.except("created_at", "updated_at") }
      Digest::SHA256.hexdigest(JSON.generate([quote.title, quote.buyer_name, source_digest(quote), rows]))
    end

    def self.enqueue(quote:, expected_revision:, destination:, currency: "USD", delivery_by: nil)
      new(quote).enqueue(expected_revision, destination, currency, delivery_by)
    end

    def self.perform(run_id)
      run = PricingRun.find_by(id: run_id)
      new(run.quote).perform(run) if run
    end

    def initialize(quote)
      @quote = quote
    end

    def enqueue(expected_revision, destination, currency, delivery_by)
      dispatch = false
      run = @quote.with_lock do
        raise Quote::StaleReview, "The RFQ changed. Review it before checking prices." unless expected_revision.is_a?(String) && expected_revision == @quote.review_revision
        validate_input!(destination, currency, delivery_by)
        active = runs.where(status: PricingRun::ACTIVE_STATUSES).order(id: :desc).first
        if active && active.current_for?(@quote) && active.destination == destination && active.currency == currency && active.delivery_by&.iso8601 == delivery_by && (active.started_at || active.queued_at) > Time.current - ACTIVE_TIMEOUT
          next active
        end
        runs.where(status: PricingRun::ACTIVE_STATUSES).update_all(status: "stale", finished_at: Time.current, error_message: "A new price check replaced this run.")
        dispatch = true
        runs.create!(source_revision: @quote.review_revision, source_digest: self.class.source_digest(@quote),
          destination: destination, currency: currency, delivery_by: delivery_by, queued_at: Time.current)
      end
      if dispatch
        begin
          fail_run(run, "The price check could not be queued. Try again.") unless PriceRfqJob.perform_later(run.id)
        rescue StandardError
          fail_run(run, "The price check could not be queued. Try again.")
        end
      end
      run.reload
    end

    def perform(run)
      snapshot = @quote.with_lock do
        run.reload
        next unless run.status == "queued" && eligible?(run)
        run.update!(status: "running", started_at: Time.current)
        @confirmed_line_snapshots = @quote.quote_lines.reload.map { |line| QuoteLine.new(line.attributes.deep_dup) }
        @confirmed_processing_revision = @quote.processing_revision&.dig("id")
        @confirmed_input_fingerprint = self.class.input_fingerprint(@quote)
        Quote.new(source_text: @quote.source_text&.dup, source_bytes: @quote.source_bytes&.dup,
          original_filename: @quote.original_filename)
      end
      return run.reload unless snapshot

      # Attachment extraction and every provider call happen outside the lock.
      source = QuoteWorkspace::SourceDocument.new(snapshot).call
      raise InputError, "The complete attachment could not be read. Upload a readable PDF, CSV or text file before pricing." if source.warnings.any?
      text = source.sections.map { |section| section.fetch(:text) }.join("\n")
      raise InputError, "No complete RFQ text is available for pricing." if text.blank?
      options = { delivery_by: run.delivery_by&.iso8601 }
      confirmed = confirmed_quantity_inputs(text, run.source_revision)
      options[:confirmed_items] = confirmed if confirmed
      result = QuoteAgent.call(rfq: text, destination: run.destination, currency: run.currency, **options)
      raise InputError, "The price check returned incomplete evidence. Existing quote lines were preserved." unless PricingRun.valid_result?(result)
      @quote.with_lock do
        run.reload
        next unless run.status == "running" && eligible?(run)
        if @confirmed_input_fingerprint != self.class.input_fingerprint(@quote)
          run.update!(status: "stale", finished_at: Time.current, error_message: STALE_MESSAGE)
          next
        end
        applied_ids = apply_ready_lines(result, run)
        result = result.deep_dup
        result["website_binding"] = { "input_fingerprint" => self.class.input_fingerprint(@quote) }
        run.update!(status: "succeeded", result: result, finished_at: Time.current,
          applied_line_ids: applied_ids, applied_revision: applied_ids.any? ? @quote.reload.review_revision : nil)
      end
      run.reload
    rescue InputError => error
      fail_run(run, error.message)
    rescue LoadError, StandardError
      fail_run(run, "The price check could not complete. Existing quote lines were preserved. Check setup and try again.")
    end

    private

    # Only persisted, resolved quantity answers can supplement intake. A free
    # text answer must itself be exactly a deterministic quantity/unit phrase,
    # and agree with the saved value and the processor's buyer evidence. SKU
    # and specification answers are deliberately not overrides here.
    def confirmed_quantity_inputs(text, revision)
      return unless @confirmed_processing_revision.present?
      intake = Intake.new.parse(rfq: text)
      rows = @confirmed_line_snapshots.filter_map do |line|
        next unless line.line_id.present? && Array(line.edited_fields).empty?
        next unless (Array(line.unresolved_fields) - ["unit_price"]).empty?
        processing = line.processing || {}
        next unless Array(processing["conflicts"]).empty? && %w[exact scored].include?(processing.dig("match", "status"))
        answered = processing["answered"]
        evidence = line.evidence["quantity"]
        next unless answered.is_a?(Hash) && answered["previous_revision"].is_a?(String) && answered["previous_revision"].present?
        next if answered["previous_revision"] == @confirmed_processing_revision || answered["rfq_text"].present? || answered["choice_id"].present?
        next unless evidence.is_a?(Hash) && evidence["location"] == "buyer answer" && evidence["text"].present?
        answer = answered["free_text"]
        next unless answer.is_a?(String) && answer == processing["answered_with"] && answer.include?(evidence["text"])
        match = answer.strip.match(/\A(?:qty|quantity)?\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(#{Intake::UNIT_PATTERN})\s*\.?\z/i)
        next unless match && line.quantity && line.quantity.positive? && BigDecimal(match[1]) == line.quantity
        unit = Intake::UNIT_MAP.fetch(match[2].downcase, match[2].downcase)
        next unless unit == line.quantity_unit
        same = @confirmed_line_snapshots.select { |other| other.original_text == line.original_text }
        parsed = intake["lines"].select { |entry| entry["original_text"] == line.original_text }
        next unless same.one? && parsed.one?
        entry = parsed.first
        next unless entry.dig("item", "part_number") == line.catalog_sku
        next unless specifications_match?(line, entry.merge("catalog_item" => entry["item"] || {}))
        # Every saved specification still requires original source evidence.
        next unless line.spec.all? { |key, value| value.blank? || (line.evidence[key].is_a?(Hash) && line.original_text.include?(line.evidence[key]["text"].to_s) && line.evidence[key]["text"].present? && line.evidence[key]["location"] != "buyer answer") }
        { "original_text" => line.original_text, "part_number" => line.catalog_sku,
          "quantity" => line.quantity.to_s("F"), "unit" => unit,
          "quote_line_id" => line.id, "evidence" => evidence.deep_dup }
      end
      Intake::ConfirmedItems.new(rfq: text, revision: revision, rows: rows) if rows.any?
    end

    def runs
      PricingRun.where(quote_id: @quote.id)
    end

    def validate_input!(destination, currency, delivery_by)
      probe = PricingRun.new(quote: @quote, destination: destination, currency: currency,
        source_revision: @quote.review_revision, source_digest: self.class.source_digest(@quote), queued_at: Time.current)
      raise InputError, "Enter a two-letter destination country, postal code and three-letter currency." unless probe.valid?
      if delivery_by
        deadline = Date.iso8601(delivery_by)
        raise InputError, "The delivery deadline must be today or later." if deadline < Date.current
      end
    rescue ArgumentError, TypeError
      raise InputError, "Enter a valid delivery date."
    end

    def eligible?(run)
      return true if run.current_for?(@quote) && !runs.where("id > ?", run.id).exists?
      run.update!(status: "stale", finished_at: Time.current, error_message: STALE_MESSAGE)
      false
    end

    # Whole-RFQ parsing may consolidate lines. Only a one-to-one identity can
    # update the existing quote. Holds never erase a rep's saved price.
    def apply_ready_lines(result, run)
      return [] unless result.dig("quote", "currency") == "USD"
      @quote.quote_lines.reload
      applied = []
      result.fetch("lines").each do |entry|
        price = entry.fetch("pricing")
        next unless price["status"] == "ready" && price["currency"] == "USD" && !entry.key?("original_lines")
        next unless Time.iso8601(price.fetch("quote_valid_until")) > Time.current
        matches = @quote.quote_lines.select do |line|
          Array(line.edited_fields).empty? && !line.rep_entered_price? &&
            (Array(line.unresolved_fields) - ["unit_price"]).empty? &&
            line.original_text == entry["original_text"] &&
            line.catalog_sku == entry.dig("catalog_item", "part_number") &&
            line.quantity_unit == entry["unit"] && line.quantity == BigDecimal(entry["quantity"].to_s) &&
            specifications_match?(line, entry)
        end
        next unless matches.one?
        line = matches.first
        next if applied.include?(line.id)
        CatalogMatch::PricingHandoff.apply(line: line, result: price)
        timing = entry["lead_time_estimate"] || {}
        if timing["status"] == "supplier_confirmed" && timing["text"].is_a?(String) && PricingRun.safe_source_url(timing["source_url"])
          line.lead_time = timing["text"].first(200)
          line.lead_time_source = "#{timing['supplier']}, #{timing['source_url']}, checked #{timing['checked_at']}".first(200)
        else
          line.lead_time = line.lead_time_source = nil
        end
        line.processing = (line.processing || {}).merge("distributor_pricing" => {
          "run_id" => run.id, "valid_until" => price["quote_valid_until"],
          "source_digest" => run.source_digest, "fingerprint" => LineValidity.fingerprint(line),
          "goods_fingerprint" => LineValidity.goods_fingerprint(line),
          "cost_before_payment_fee" => price.dig("cost_breakdown", "total_before_payment_fee"),
          "payment_fee_rate" => price.dig("cost_breakdown", "payment_fee_rate")
        })
        line.save!
        applied << line.id
      end
      applied
    end

    def specifications_match?(line, entry)
      requested = entry.fetch("reading", {}).merge(entry.fetch("catalog_item", {}))
      keys = { "thickness" => "thickness_in", "width" => "width_in", "length" => "length_in",
        "diameter" => "diameter_in", "grip" => "grip_length_in" }
      line.spec.all? do |key, value|
        next true if value.blank?
        actual = requested[keys.fetch(key, key)]
        next false if actual.nil?
        if keys.key?(key)
          match = value.to_s.match(/\A(\d+(?:\.\d+)?)\s*(?:in|inch|inches)\z/i)
          match && BigDecimal(match[1]) == BigDecimal(actual.to_s)
        else
          value.to_s.strip.casecmp?(actual.to_s.strip)
        end
      end
    rescue ArgumentError, TypeError
      false
    end

    def fail_run(run, message)
      @quote.with_lock do
        run.reload
        run.update!(status: "failed", error_message: message, finished_at: Time.current) if run.active? && eligible?(run)
      end
      run.reload
    end
  end
end
