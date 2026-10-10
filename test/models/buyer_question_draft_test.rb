require "test_helper"

class BuyerQuestionDraftTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "draft-test")
    @draft = QuoteWorkspace::BuyerQuestionDraft.new(@quote)
  end

  test "draft includes existing questions in original line order with sample notice" do
    assert @draft.ready?
    assert_equal [ 2, 3 ], @draft.held_lines.map(&:position)
    assert_empty @draft.missing_question_lines
    assert_equal "Questions about #{@quote.reference}", @draft.subject
    assert_equal "SAMPLE-#{@quote.reference}-buyer-questions.txt", @draft.filename
    assert_includes @draft.body, "Draft, not sent"
    assert_includes @draft.body, "SAMPLE DATA: Synthetic RFQ"
    assert_includes @draft.body, "Buyer: #{@quote.buyer_name}"
    @draft.held_lines.each { |line| assert_includes @draft.body, "Line #{line.position}\n#{line.clarification_question}" }
    assert_operator @draft.body.index("Line 2"), :<, @draft.body.index("Line 3")
  end

  test "only held questions and buyer metadata enter the draft" do
    @quote.quote_lines.second.update!(notes: "SECRET-INTERNAL-NOTE", original_text: "PRIVATE-SOURCE-LINE", unit_price: 812.4567)
    @quote.update!(source_text: "FULL-PRIVATE-RFQ", source_bytes: "SECRET-BYTES", original_filename: "PRIVATE-FILE.txt", title: "PRIVATE-TITLE")
    body = @draft.body
    %w[SECRET-INTERNAL-NOTE PRIVATE-SOURCE-LINE 812.4567 232 4640 FULL-PRIVATE-RFQ SECRET-BYTES PRIVATE-FILE PRIVATE-TITLE].each do |private_value|
      refute_includes body, private_value
    end
    refute_includes body, @quote.quote_lines.first.original_text
  end

  test "whitespace question blocks the whole draft without inventing a replacement" do
    line = @quote.quote_lines.second
    line.update!(clarification_question: " \n ")
    assert_equal [ line.id ], @draft.missing_question_lines.map(&:id)
    refute @draft.ready?
    assert_raises(QuoteWorkspace::BuyerQuestionDraft::Incomplete) { @draft.body }
  end

  test "no held lines and empty quotes cannot produce a draft" do
    @quote.quote_lines.where.not(state: "ready").delete_all
    refute @draft.ready?
    assert_raises(QuoteWorkspace::BuyerQuestionDraft::Incomplete) { @draft.body }
    @quote.quote_lines.delete_all
    empty_draft = QuoteWorkspace::BuyerQuestionDraft.new(@quote.reload)
    assert_empty empty_draft.held_lines
    refute empty_draft.ready?
  end

  test "invalid ready lines are held even if their stored state says ready" do
    @quote.quote_lines.first.update_columns(catalog_sku: nil)
    refute @draft.ready?
    assert_equal [ 1 ], @draft.missing_question_lines.map(&:position)
  end

  test "real data has no synthetic label and missing buyer is omitted" do
    @quote.update!(sample_data: false, buyer_name: nil)
    assert_equal "#{@quote.reference}-buyer-questions.txt", @draft.filename
    refute_includes @draft.body, "SAMPLE"
    refute_includes @draft.body, "Buyer:"
  end
end
