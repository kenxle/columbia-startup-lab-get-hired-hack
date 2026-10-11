require "test_helper"
require "minitest/mock"
require Rails.root.join("tools/distributor_pricing/lib/distributor_pricing/agent").to_s

class DistributorConfirmedInputRunTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @quote = Quote.create!(title: "Confirmed pricing test", workspace_token: "confirmed-test",
      source_text: "S-330 steel shot, lb\nS-170 steel shot, 100 lb")
    matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(client: nil,
      catalog: CatalogMatch::Catalog.new(%w[rudco metals]), service: CatalogMatch::Matcher)
    QuoteWorkspace::ApplyResult.call(quote: @quote,
      result: RfqProcessing.process(content: @quote.source_text, matcher: matcher, llm: false))
    @line = @quote.quote_lines.first
    QuoteWorkspace::ApplyBuyerAnswer.call(quote: @quote, quote_line_id: @line.id,
      reviewed_version: @quote.reload.review_revision, revision_id: @quote.processing_revision.fetch("id"), free_text: "2000 lb")
    @line.reload
    clear_enqueued_jobs
  end

  def check(&during_refresh)
    run = DistributorPricing::Run.enqueue(quote: @quote, expected_revision: @quote.reload.review_revision,
      destination: { "country" => "US", "postal_code" => "10027" })
    @requests = []
    book = Object.new
    requests = @requests
    book.define_singleton_method(:refresh) do |items:, request:|
      requests << request
      during_refresh.call if during_refresh
      {}
    end
    markets = Object.new
    markets.define_singleton_method(:refresh) { {} }
    markets.define_singleton_method(:for_item) { |item, snapshot:| { "status" => "unavailable" } }
    agent = DistributorPricing::Agent.new(source_book: book, market_context: markets)
    DistributorPricing::Agent.stub(:configured, ->(**) { agent }) { DistributorPricing::Run.perform(run.id) }
    run.reload
  end

  test "persisted buyer quantity reaches a fresh agent call without rewriting source" do
    original = @quote.source_text
    run = check
    assert_equal "succeeded", run.status, run.error_message
    assert_equal "2000.0", run.result["lines"][0]["quantity"]
    assert_equal "2000.0", @requests.first["items"].find { |item| item["part_number"] == @line.catalog_sku }["quantity"]
    assert_equal "S-330 steel shot, lb", run.result["lines"][0]["original_text"]
    assert_equal 2, run.result["original_rfq_line_count"]
    assert_equal "100", run.result["lines"][1]["quantity"]
    assert_equal Digest::SHA256.hexdigest(original), run.result.dig("request", "rfq_sha256")
    assert_equal original, @quote.reload.source_text
    assert_equal "needs_procurement", run.result["lines"][0]["pricing"]["status"]
    assert_empty run.applied_line_ids
  end

  test "a persisted edit during provider refresh makes the run stale" do
    run = check { @line.update!(quantity: 3000) }
    assert_equal "stale", run.status
    assert_empty run.applied_line_ids
    assert_equal BigDecimal("3000"), @line.reload.quantity
  end

  test "changed original source cannot reuse an earlier answer" do
    @quote.update!(source_text: "S-330 steel shot, 99 lb\nS-170 steel shot, 100 lb")
    run = check
    assert_equal "succeeded", run.status, run.error_message
    assert_equal "99", run.result["lines"][0]["quantity"]
    assert_nil run.result["lines"][0]["confirmed_input"]
  end

  test "edits conflicts and forged answer evidence cannot authorize quantity" do
    [ { edited_fields: ["quantity"] },
      { processing: @line.processing.merge("conflicts" => [{ "message" => "conflicting" }]) },
      { evidence: @line.evidence.merge("quantity" => { "text" => "999 lb", "location" => "buyer answer" }) },
      { processing: @line.processing.merge("answered" => @line.processing["answered"].merge("previous_revision" => @quote.processing_revision["id"])) } ].each do |changes|
      original = @line.attributes
      @line.update!(changes)
      run = check
      assert_equal "succeeded", run.status, run.error_message
      assert_nil run.result["lines"][0]["quantity"]
      @line.update!(original.except("id", "created_at", "updated_at"))
    end
  end
end
