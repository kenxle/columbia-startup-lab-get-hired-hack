require "test_helper"
require "minitest/mock"

class ApplyBuyerAnswerTest < ActiveSupport::TestCase
  setup do
    @quote = Quote.create!(title: "Answer review", source_text: "S-330 steel shot, lb\nS-330 steel shot, 100 lb", workspace_token: "answer-test")
    matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(client: nil, catalog: CatalogMatch::Catalog.new(%w[rudco metals]), service: CatalogMatch::Matcher)
    result = RfqProcessing.process(content: @quote.source_text, matcher: matcher, llm: false)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
    @line = @quote.quote_lines.first
  end

  def arguments
    {quote: @quote, quote_line_id: @line.id, reviewed_version: @quote.reload.review_revision,
      revision_id: @quote.processing_revision.fetch("id"), free_text: "100 lb"}
  end

  test "free text reruns only the held line preserving other edits and clearing approval" do
    untouched = @quote.quote_lines.last
    untouched.apply_manual_edit("notes" => "Rep note to preserve")
    @quote.approve!
    before = untouched.reload.attributes
    stable_id = @line.line_id
    old_revision = @quote.processing_revision["id"]
    result = QuoteWorkspace::ApplyBuyerAnswer.call(**arguments)
    assert_equal @line.id, result.id
    assert_equal stable_id, result.line_id
    assert result.quotable?
    assert_equal BigDecimal("0.4"), result.unit_price
    assert_equal "S-330 steel shot, lb", result.original_text
    assert_equal "100 lb", result.processing.dig("answered", "free_text")
    assert_equal before, untouched.reload.attributes
    refute @quote.reload.approved?
    refute_equal old_revision, @quote.processing_revision["id"]
  end

  test "a still incomplete answer remains held and unpriced" do
    result = QuoteWorkspace::ApplyBuyerAnswer.call(**arguments.merge(free_text: "Please confirm"))
    refute result.quotable?
    assert_nil result.unit_price
    assert result.clarification_question.present?
  end

  test "stale review and processing revisions are rejected without writes" do
    before = @quote.quote_lines.map(&:attributes)
    [{reviewed_version: "stale"}, {revision_id: "stale"}, {revision_id: nil}].each do |changes|
      assert_raises(Quote::StaleReview) { QuoteWorkspace::ApplyBuyerAnswer.call(**arguments.merge(changes)) }
    end
    assert_equal before, @quote.quote_lines.reload.map(&:attributes)
  end

  test "blank oversize conflicting and unknown choice answers are rejected" do
    [{free_text: " "}, {free_text: "x" * 2001}, {choice_id: "unknown"},
      {choice_id: "unknown", free_text: nil}, {free_text: []}].each do |changes|
      assert_raises(QuoteWorkspace::ApplyBuyerAnswer::Invalid) { QuoteWorkspace::ApplyBuyerAnswer.call(**arguments.merge(changes)) }
    end
  end

  test "ready lines rep edits and active runs block answers" do
    assert_raises(QuoteWorkspace::ApplyBuyerAnswer::Invalid) do
      QuoteWorkspace::ApplyBuyerAnswer.call(**arguments.merge(quote_line_id: @quote.quote_lines.last.id))
    end
    @line.update!(edited_fields: ["quantity"])
    assert_raises(QuoteWorkspace::ApplyBuyerAnswer::Invalid) { QuoteWorkspace::ApplyBuyerAnswer.call(**arguments) }
    @line.update!(edited_fields: [])
    @quote.processing_runs.create!(status: "running", requested_revision: @quote.review_revision, source_revision: @quote.review_revision, queued_at: Time.current)
    assert_raises(QuoteWorkspace::ApplyBuyerAnswer::Invalid) { QuoteWorkspace::ApplyBuyerAnswer.call(**arguments) }
  end

  test "late result cannot overwrite a concurrent rep edit" do
    actual = RfqProcessing::Answers.method(:apply)
    RfqProcessing::Answers.stub(:apply, ->(**input) {
      result = actual.call(**input)
      @line.apply_manual_edit("notes" => "Changed while processing")
      result
    }) do
      assert_raises(Quote::StaleReview) { QuoteWorkspace::ApplyBuyerAnswer.call(**arguments) }
    end
    assert_equal "Changed while processing", @line.reload.notes
    refute @line.quotable?
  end

  test "invalid processor line rolls back without clearing approval" do
    @quote.approve!
    before = @quote.quote_lines.map(&:attributes)
    old_revision = @quote.processing_revision.deep_dup
    actual = RfqProcessing::Answers.method(:apply)
    RfqProcessing::Answers.stub(:apply, ->(**input) {
      result = actual.call(**input)
      result["lines"].first["quantity"] = -1
      result
    }) do
      assert_raises(QuoteWorkspace::ApplyBuyerAnswer::Invalid) { QuoteWorkspace::ApplyBuyerAnswer.call(**arguments) }
    end
    assert_equal before, @quote.quote_lines.reload.map(&:attributes)
    assert_equal old_revision, @quote.reload.processing_revision
    assert @quote.approved?
  end

  test "choice membership is scoped to target line" do
    @quote.quote_lines.last.update!(processing: {"question_choices" => [{"id" => "other-choice", "field" => "quantity", "value" => 100, "label" => "100"}]})
    assert_raises(QuoteWorkspace::ApplyBuyerAnswer::Invalid) do
      QuoteWorkspace::ApplyBuyerAnswer.call(**arguments.merge(free_text: nil, choice_id: "other-choice"))
    end
  end

  test "known field choice reaches the library with stable identity" do
    @line.update!(processing: @line.processing.merge("question_choices" => [
      {"id" => "quantity-choice", "field" => "quantity", "value" => 100, "label" => "100"}
    ]))
    result = QuoteWorkspace::ApplyBuyerAnswer.call(**arguments.merge(free_text: nil, choice_id: "quantity-choice"))
    assert_equal @line.line_id, result.line_id
    assert_equal BigDecimal("100"), result.quantity
    assert_equal "quantity-choice", result.processing.dig("answered", "choice_id")
    refute result.quotable?, "The missing sale unit must still hold the line"
  end

  test "catalog choice cannot promote a closest or conflicting item" do
    catalog = CatalogMatch::Catalog.new(["rudco"])
    item = catalog.find("RC-STEELSHOT-S330")
    candidate = CatalogMatch::Matcher::Candidate.new(item: item, checks: [{field: "grade", status: :conflict}])
    matcher = QuoteWorkspace::ApplyBuyerAnswer::AnswerMatcher.new(catalog: catalog, service: CatalogMatch::Matcher)
    matcher.chosen_item = item["pn"]
    %w[no_match candidates].each do |outcome|
      result = CatalogMatch::Matcher::Result.new(outcome: outcome, candidates: [candidate], closest: [candidate])
      CatalogMatch::Matcher.stub(:call, ->(*) { result }) do
        assert_raises(QuoteWorkspace::ApplyBuyerAnswer::Invalid) do
          matcher.match(line_text: "S-330 steel shot", quantity: 100, quantity_unit: "lb")
        end
      end
    end
  end

  test "choosing a candidate cannot use pound pricing for kilogram quantities" do
    catalog = CatalogMatch::Catalog.new(["rudco"])
    item = catalog.find("RC-STEELSHOT-S330")
    candidate = CatalogMatch::Matcher::Candidate.new(item: item, checks: [{field: "grade", status: :exact}])
    matcher = QuoteWorkspace::ApplyBuyerAnswer::AnswerMatcher.new(catalog: catalog, service: CatalogMatch::Matcher)
    matcher.chosen_item = item["pn"]
    result = CatalogMatch::Matcher::Result.new(outcome: "candidates", candidates: [candidate], closest: [])
    CatalogMatch::Matcher.stub(:call, ->(*) { result }) do
      output = matcher.match(line_text: "S-330 steel shot", quantity: 100, quantity_unit: "kg")
      assert_nil output["candidates"].sole["list_price_usd_per_lb"]
      assert_nil output["best"]
    end
  end
end
