require "test_helper"

class QuoteReviewRevisionTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "review-revision-test")
  end

  test "a manual edit of an unapproved quote rejects an older review" do
    review = Quote.find(@quote.id)
    revision = review.review_revision

    assert @quote.quote_lines.first.apply_manual_edit("notes" => "Updated delivery instructions")
    assert_not_equal revision, @quote.reload.review_revision
    assert_raises(Quote::StaleReview) { review.approve!(expected_revision: revision) }
    refute @quote.reload.approved?
  end

  test "a fresh review approves and a subsequent edit clears approval" do
    @quote.approve!(expected_revision: @quote.review_revision)
    assert @quote.reload.approved?

    assert @quote.quote_lines.first.apply_manual_edit("notes" => "Needs new review")
    refute @quote.reload.approved?
  end

  test "two edits with the clock frozen still produce distinct revisions" do
    freeze_time do
      line = @quote.quote_lines.first
      revisions = [ @quote.review_revision ]
      2.times do |index|
        assert line.apply_manual_edit("notes" => "Revision #{index}")
        revisions << @quote.reload.review_revision
      end
      assert_equal 3, revisions.uniq.length
    end
  end

  test "a failed manual edit preserves persisted revision and approval" do
    @quote.approve!
    revision = @quote.review_revision
    line = @quote.quote_lines.first

    refute line.apply_manual_edit("quantity" => "invalid")
    assert line.errors[:quantity].any?
    assert_equal BigDecimal("20"), line.reload.quantity
    assert_equal revision, @quote.reload.review_revision
    assert @quote.approved?
  end

  test "invalid imported rows roll back replacement and preserve approval and revision" do
    @quote.approve!
    revision = @quote.review_revision
    original_ids = @quote.quote_lines.pluck(:id)
    result = result_for_quote
    result["lines"].last["description"] = "x" * 501

    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) do
      QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
    end

    assert_equal original_ids, @quote.quote_lines.pluck(:id)
    assert_equal revision, @quote.reload.review_revision
    assert @quote.approved?
  end

  test "BigDecimal results import and invalidate the earlier review" do
    revision = @quote.review_revision
    result = result_for_quote
    result["lines"].first["quantity"] = BigDecimal("20")
    result["lines"].first["unit_price"] = BigDecimal("232.50")

    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)

    assert_equal BigDecimal("232.50"), @quote.quote_lines.first.unit_price
    assert_not_equal revision, @quote.review_revision
    assert_raises(Quote::StaleReview) { @quote.approve!(expected_revision: revision) }
  end

  test "a no match result requires a buyer question" do
    result = result_for_quote
    result["lines"].last["clarification_question"] = " "

    error = assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) do
      QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
    end
    assert_match(/No match but has no clarification question/, error.message)
  end

  test "approval invalidation does not revalidate unchanged quote source" do
    @quote.update_columns(source_text: nil, source_bytes: nil)
    assert @quote.quote_lines.first.apply_manual_edit("notes" => "Imported quote follow-up")
    refute @quote.reload.approved?
  end

  private

  def result_for_quote
    {
      "schema_version" => 1,
      "sample_data" => true,
      "lines" => @quote.quote_lines.map do |line|
        line.attributes.slice(*QuoteWorkspace::ApplyResult::LINE_KEYS)
      end
    }
  end
end
