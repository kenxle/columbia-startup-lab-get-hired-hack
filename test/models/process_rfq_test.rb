require "test_helper"
require "minitest/mock"

class ProcessRfqTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @quote = Quote.create!(title: "RFQ", source_text: "304 SS sheet 16ga 4x8, 20 sheets, MTRs required",
      workspace_token: "process-rfq-test")
  end

  def enqueue
    QuoteWorkspace::ProcessRfq.enqueue(quote: @quote, expected_revision: @quote.reload.review_revision)
  end

  def perform(run)
    QuoteWorkspace::ProcessRfq.perform(run.id)
  end

  test "initial real processing persists an honest unpriced result and finishes idempotently" do
    run = nil
    assert_enqueued_jobs 1, only: ProcessRfqJob do
      run = enqueue
    end
    assert_equal "queued", run.status
    assert_equal @quote.review_revision, run.source_revision
    assert_equal "succeeded", perform(run).status
    line = @quote.reload.quote_lines.first
    assert line
    assert_nil line.unit_price
    refute line.quotable?
    assert @quote.sample_data?
    assert run.reload.started_at
    assert run.finished_at
    line_ids = @quote.quote_lines.ids
    RfqProcessing.stub(:process, ->(**) { flunk "Finished job must not process twice" }) { perform(run) }
    assert_equal line_ids, @quote.reload.quote_lines.ids
  end

  test "duplicate active requests return one run and do not enqueue twice" do
    requested = @quote.review_revision
    run = enqueue
    assert_no_enqueued_jobs do
      duplicate = QuoteWorkspace::ProcessRfq.enqueue(quote: @quote, expected_revision: requested)
      assert_equal run.id, duplicate.id
    end
    assert_equal 1, ProcessingRun.where(quote: @quote).count
    [nil, "wrong"].each do |revision|
      assert_raises(Quote::StaleReview) do
        QuoteWorkspace::ProcessRfq.enqueue(quote: @quote, expected_revision: revision)
      end
    end
  end

  test "approval is invalidated before processing and post-invalidation revision is captured" do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "approved-process")
    @quote.approve!
    approved_revision = @quote.review_revision
    run = enqueue

    refute @quote.reload.approved?
    assert_equal approved_revision, run.requested_revision
    assert_equal @quote.review_revision, run.source_revision
    refute_equal approved_revision, run.source_revision
  end

  test "rep edits block full replacement without changing lines or approval" do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "edited-process")
    @quote.quote_lines.first.apply_manual_edit("notes" => "Rep promise")
    @quote.reload.approve!
    originals = @quote.quote_lines.map(&:attributes)
    assert_no_enqueued_jobs do
      run = enqueue
      assert_equal "conflict", run.status
      assert_match(/rep edits/, run.error_message)
    end
    assert_equal originals, @quote.reload.quote_lines.map(&:attributes)
    assert @quote.approved?
  end

  test "edits during processor call are preserved and produce conflict" do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "mid-process-edit")
    run = enqueue
    RfqProcessing.stub(:process, lambda { |**|
      @quote.quote_lines.first.apply_manual_edit("description" => "Rep description")
      QuoteWorkspace::Demo.result
    }) { perform(run) }
    assert_equal "conflict", run.reload.status
    assert_equal "Rep description", @quote.reload.quote_lines.first.description
  end

  test "newer processing results make old job stale instead of overwriting" do
    run = enqueue
    RfqProcessing.stub(:process, lambda { |**|
      QuoteWorkspace::ApplyResult.call(quote: @quote, result: QuoteWorkspace::Demo.result)
      QuoteWorkspace::Demo.result
    }) { perform(run) }

    assert_equal "stale", run.reload.status
    assert_equal 3, @quote.reload.quote_lines.count
  end

  test "model import failure preserves old lines and metadata without partial rows" do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "invalid-result")
    originals = @quote.quote_lines.map(&:attributes)
    run = enqueue
    result = QuoteWorkspace::Demo.result
    result["lines"].second["description"] = "x" * 501
    RfqProcessing.stub(:process, result) { perform(run) }

    assert_equal "failed", run.reload.status
    assert_equal originals, @quote.reload.quote_lines.map(&:attributes)
    assert_match(/preserved/, run.error_message)
  end

  test "warning-only extraction failure is visible and keeps existing lines" do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "warning-result")
    originals = @quote.quote_lines.ids
    run = enqueue
    result = {"lines" => [], "warnings" => ["PDF has no text; OCR needed"],
      "source" => {"type" => "pdf", "pages" => 1, "filename" => "scan.pdf", "rows" => nil}}
    RfqProcessing.stub(:process, result) { perform(run) }

    assert_equal "failed", run.reload.status
    assert_includes run.warnings, "PDF has no text; OCR needed"
    assert_includes @quote.reload.processing_warnings, "PDF has no text; OCR needed"
    assert_equal originals, @quote.quote_lines.ids
  end

  test "unsupported Excel and raw MIME fail honestly without invoking parser" do
    {"rfq.xlsx" => /CSV/, "rfq.xls" => /CSV/, "rfq.eml" => /Raw email/}.each do |filename, message|
      @quote.update!(source_bytes: "fake source", original_filename: filename)
      run = enqueue
      RfqProcessing.stub(:process, ->(**) { flunk "Unsupported source must not reach parser" }) { perform(run) }
      assert_equal "failed", run.reload.status
      assert_match message, run.error_message
    end
  end

  test "CSV and PDF adapter pass original bytes and constrained sample matcher" do
    {"rfq.csv" => "csv", "rfq.pdf" => "pdf"}.each do |filename, type|
      @quote.update!(source_bytes: "source bytes", original_filename: filename)
      run = enqueue
      RfqProcessing.stub(:process, lambda { |**input|
        assert_equal "source bytes", input[:content]
        assert_equal type, input[:type]
        assert_equal filename, input[:filename]
        assert_kind_of QuoteWorkspace::ProcessRfq::IntakeMatcher, input[:matcher]
        assert_equal [], input[:buyer_terms]
        assert_equal true, input[:sample_data]
        assert_equal false, input[:llm]
        QuoteWorkspace::Demo.result
      }) { perform(run) }
      assert_equal "succeeded", run.reload.status
    end
  end

  test "processor exception becomes bounded human error without exposing internals" do
    run = enqueue
    RfqProcessing.stub(:process, ->(**) { raise "secret-key-sensitive-trace" }) { perform(run) }

    assert_equal "failed", run.reload.status
    refute_includes run.error_message, "secret-key"
    assert_operator run.error_message.length, :<=, 1_000
    assert @quote.reload.awaiting_processing?
  end

  test "explicit retry reclaims expired queued and running jobs" do
    %w[queued running].each do |status|
      run = enqueue
      run.update!(status: status, started_at: status == "running" ? Time.current : nil)
      travel 4.minutes do
        assert_no_enqueued_jobs { assert_equal run.id, enqueue.id }
        assert_equal status, run.reload.status
      end
      travel 6.minutes do
        replacement = nil
        assert_enqueued_jobs 1, only: ProcessRfqJob do
          replacement = enqueue
        end
        assert_equal "stale", run.reload.status
        assert run.finished_at
        assert_equal "queued", replacement.status
        refute_equal run.id, replacement.id
        assert_equal @quote.reload.review_revision, replacement.source_revision
        # Resolve this replacement so the next loop starts with a fresh run.
        perform(replacement)
      end
    end
  end

  test "an expired worker finishing after a retry cannot apply its late result" do
    old_run = enqueue
    replacement = nil
    calls = 0
    RfqProcessing.stub(:process, lambda { |**|
      calls += 1
      if calls > 1
        fresh = QuoteWorkspace::Demo.result
        fresh["lines"].first["description"] = "Current retry result"
        next fresh
      end
      travel 6.minutes do
        replacement = enqueue
        perform(replacement)
      end
      late = QuoteWorkspace::Demo.result
      late["lines"].first["description"] = "Late old result"
      late
    }) { perform(old_run) }

    assert_equal "stale", old_run.reload.status
    assert_equal 2, calls
    assert_equal "succeeded", replacement.reload.status
    assert_equal "Current retry result", @quote.reload.quote_lines.first.description
  end

  test "missing processor dependencies become actionable failures" do
    run = enqueue
    RfqProcessing.stub(:process, ->(**) { raise LoadError, "private dependency path" }) { perform(run) }

    assert_equal "failed", run.reload.status
    assert_match(/dependency is unavailable/, run.error_message)
    refute_includes run.error_message, "private dependency path"
  end

  test "steel shot intake uses a traceable RudCo list reference per pound" do
    @quote.update!(source_text: "S-330 steel shot, 100 lb")
    run = perform(enqueue)
    assert_equal "succeeded", run.status, run.error_message
    line = @quote.reload.quote_lines.first

    assert line.quotable?, line.clarification_question
    assert_equal "lb", line.quantity_unit
    assert line.catalog_sku.start_with?("RC-")
    assert_includes line.price_source, "rud-co.com"
    assert_equal "list_price", line.benchmark["kind"]
    assert line.benchmark["as_of"].present?
    assert_equal "USD per lb", line.benchmark["unit"]
    assert @quote.sample_data?
    refute @quote.approved?
  end

  test "A36 plate without an established priced match stays held and unpriced" do
    @quote.update!(source_text: 'A36 plate 1/4" x 48" x 96", 10 sheets')
    run = perform(enqueue)
    assert_equal "succeeded", run.status, run.error_message
    line = @quote.reload.quote_lines.first

    refute line.quotable?
    assert_nil line.unit_price
    assert_nil line.line_total
    assert line.clarification_question.present?
    assert_equal BigDecimal("0"), @quote.subtotal
  end

  test "explicit catalog part numbers require rep review and preserve prior lines" do
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: QuoteWorkspace::Demo.result)
    original_ids = @quote.quote_lines.pluck(:id)
    ["RC-STEELSHOT-S330 steel shot S-780, 100 lb",
      "S780 steel shot RC-STEELSHOT-S330, 100 lb",
      "rc-steelshot-s330 steel shot S-330, 100 lb",
      "RC-STEELSHOT-S330 aluminum 16ga, 100 lb"].each do |source|
      @quote.update!(source_text: source)
      run = perform(enqueue)
      assert_equal "failed", run.status
      assert_match(/catalog part numbers require rep review/, run.error_message)
      assert_equal original_ids, @quote.reload.quote_lines.pluck(:id)
    end
  end

  test "ordinary shot description retains sourced price without a catalog part number" do
    @quote.update!(source_text: "S-330 steel shot, 100 lb")
    run = perform(enqueue)
    assert_equal "succeeded", run.status, run.error_message
    line = @quote.reload.quote_lines.first
    assert line.quotable?
    assert_equal "RC-STEELSHOT-S330", line.catalog_sku
    assert_equal BigDecimal("0.4"), line.unit_price
  end

  test "catalog PN safeguard also covers metals and preserves ordinary P1020 intake" do
    part_number = CatalogMatch::Catalog.new(["metals"]).part_numbers.first
    @quote.update!(source_text: "#{part_number}, 100 lb")
    run = perform(enqueue)
    assert_equal "failed", run.status
    assert_match(/catalog part numbers require rep review/, run.error_message)
    assert @quote.reload.quote_lines.empty?

    @quote.update!(source_text: "P1020 aluminum ingot, 100 lb")
    run = perform(enqueue)
    assert_equal "succeeded", run.status, run.error_message
    assert @quote.reload.quote_lines.any?
  end

  test "conflicting stainless gauge readings stay held with evidence" do
    @quote.update!(source_text: '304 stainless sheet 16 ga .060" 48 x 96, 20 sheets')
    run = perform(enqueue)
    assert_equal "succeeded", run.status, run.error_message
    line = @quote.reload.quote_lines.first

    refute line.quotable?
    assert_nil line.unit_price
    assert line.unresolved_fields.any?
    assert line.processing["conflicts"].any?
    assert_includes line.original_text, "16 ga"
    assert line.clarification_question.present?
  end

  test "aviation catalog is excluded from automatic intake" do
    @quote.update!(source_text: "AN3-13A bolts, 100 ea")
    run = perform(enqueue)
    assert_equal "succeeded", run.status, run.error_message
    line = @quote.reload.quote_lines.first
    refute line.quotable?
    assert_nil line.unit_price
    assert_nil line.catalog_sku
  end

  test "per-pound prices are not applied to bag or kilogram quantities" do
    ["S-330 steel shot, 100 kg", "S-330 steel shot, 10 bags"].each do |source|
      @quote.update!(source_text: source)
      run = perform(enqueue)
      assert_equal "succeeded", run.status, run.error_message
      line = @quote.reload.quote_lines.first
      refute line.quotable?
      assert_nil line.unit_price
      assert_nil line.line_total
    end
  end

  test "intake forwards only the current buyer context into parsing and matching" do
    @quote.update!(buyer_name: "Northline")
    context = QuoteWorkspace::BuyerContext.for(@quote)
    context[:client].client_terms.create!(term: "our finish", meaning: {"fields" => {"finish" => "2B"}},
      source: "taught", times_confirmed: 1)
    context[:client].client_terms.create!(term: "urgent", meaning: {"fields" => {"grade" => "304"}},
      source: "learned", times_confirmed: 1)
    run = enqueue
    RfqProcessing.stub(:process, lambda { |**input|
      term = input[:buyer_terms].sole
      assert_equal false, input[:llm]
      assert_equal "our finish", term["term"]
      assert_equal "Northline", term["client_name"]
      assert_nil input[:matcher].instance_variable_get(:@client)
      catalog = input[:matcher].instance_variable_get(:@catalog)
      assert_equal %w[metals rudco], catalog.items.map { |entry| entry["catalog"] }.uniq.sort
      QuoteWorkspace::Demo.result
    }) { perform(run) }
    assert_equal "succeeded", run.reload.status
  end

  test "intake holds nonpositive catalog list prices" do
    [nil, 0, -1].each do |price|
      item = CatalogMatch::Catalog.new(["rudco"]).items.find { |entry| entry["pn"].include?("S330") }
      assert item
      item = item.merge("list_price_usd_per_lb" => price)
      catalog = CatalogMatch::Catalog.new(items: [item])
      matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(client: nil, catalog: catalog, service: CatalogMatch::Matcher)
      result = RfqProcessing.process(content: "S-330 steel shot, 100 lb", matcher: matcher)
      line = result["lines"].first
      assert_equal "needs_buyer", line["state"]
      assert_nil line["unit_price"]
      assert_includes line["unresolved_fields"], "unit_price"
    end
  end

  test "matcher exceptions fail the run instead of claiming no catalog match" do
    @quote.update!(source_text: "S-330 steel shot, 100 lb")
    run = enqueue
    CatalogMatch::Matcher.stub(:call, ->(*) { raise "private matcher failure" }) { perform(run) }

    assert_equal "failed", run.reload.status
    assert_match(/matching is temporarily unavailable/, run.error_message)
    refute_includes run.error_message, "private matcher failure"
    assert @quote.reload.awaiting_processing?
  end

  test "rules intake never initializes or reads the configured catalog provider" do
    defaults = 0
    provider = Object.new
    provider.define_singleton_method(:read) { |*| raise "Catalog provider must not read intake" }
    CatalogMatch::LlmReader.stub(:default, lambda {
      defaults += 1
      provider
    }) do
      ["S-330 steel shot, 100 lb", "mystery special material, 100 lb"].each do |source|
        @quote.update!(source_text: source)
        assert_equal "succeeded", perform(enqueue).status
      end
    end
    assert_equal 0, defaults
    refute @quote.reload.quote_lines.first.quotable?
  end

  test "rules boundary preserves an injected matcher without requiring an llm keyword" do
    catalog = CatalogMatch::Catalog.new(%w[rudco metals])
    seen = []
    service = lambda do |text, client:, catalog:|
      seen << [text, client, catalog]
      CatalogMatch::Matcher.call(text, client: client, catalog: catalog, llm: false)
    end
    matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(catalog: catalog, service: service)
    result = matcher.match(line_text: "S-330 steel shot", quantity: 100, quantity_unit: "lb")
    assert_equal [["S-330 steel shot", nil, catalog]], seen
    assert_equal "RC-STEELSHOT-S330", result.fetch("best").fetch("item_id")
  end

  test "rules boundary accepts normalized spec and quantity from the new adapter" do
    adapter = Class.new(QuoteWorkspace::ProcessRfq::IntakeMatcher) do
      private

      def given_spec(spec, quantity: nil)
        { "thickness" => spec.fetch("thickness_in"), "quantity" => quantity }
      end
    end
    catalog = CatalogMatch::Catalog.new(%w[rudco metals])
    matcher = adapter.new(client: Object.new, catalog: catalog, service: CatalogMatch::Matcher)
    called = false
    CatalogMatch::Matcher.stub(:call, lambda { |text, client:, catalog:, given:, llm:|
      called = true
      assert_equal "304 stainless sheet", text
      assert_nil client
      assert_equal %w[metals rudco], catalog.items.map { |item| item["catalog"] }.uniq.sort
      assert_equal({ "thickness" => 0.0625, "quantity" => 6 }, given)
      assert_equal false, llm
      :matched
    }) do
      assert_equal :matched, matcher.send(:call_service, "304 stainless sheet", { "thickness_in" => 0.0625 }, 6)
    end
    assert called
  end

  test "intake pins the restricted matcher and never calls the automatic contract" do
    CatalogMatch::Contract.stub(:call, ->(*) { flunk "Unrestricted contract must not run" }) do
      @quote.update!(source_text: "S-330 steel shot, 100 lb")
      assert_equal "succeeded", perform(enqueue).status
      assert @quote.reload.quote_lines.first.quotable?

      @quote.update!(source_text: "AN3-13A bolts, 100 ea")
      assert_equal "succeeded", perform(enqueue).status
      refute @quote.reload.quote_lines.first.quotable?
      assert_nil @quote.quote_lines.first.catalog_sku

      @quote.update!(source_text: "RC-STEELSHOT-S330, 100 lb")
      assert_equal "failed", perform(enqueue).status
    end
  end

  test "single near candidate stays held instead of becoming a scored best" do
    item = CatalogMatch::Catalog.new(["rudco"]).find("RC-STEELSHOT-S330")
    candidate = CatalogMatch::Matcher::Candidate.new(item: item, checks: [
      {field: "material", status: :exact}, {field: "grade", status: :exact},
      {field: "form", status: :exact}, {field: "finish", status: :near, explanation: "Confirm finish"}
    ])
    result = CatalogMatch::Matcher::Result.new(outcome: "candidates", candidates: [candidate], closest: [], question: "Confirm finish?")
    @quote.update!(source_text: "S-330 steel shot, 100 lb")
    CatalogMatch::Contract.stub(:call, ->(*) { flunk "Unrestricted contract must not run" }) do
      CatalogMatch::Matcher.stub(:call, ->(*) { result }) do
        assert_equal "succeeded", perform(enqueue).status
      end
    end
    line = @quote.reload.quote_lines.first
    refute line.quotable?
    assert_nil line.unit_price
    assert line.clarification_question.present?
  end
end
