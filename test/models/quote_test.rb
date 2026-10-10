require "test_helper"

class QuoteTest < ActiveSupport::TestCase
  WORKSPACE_TOKEN = "quote-model-test-workspace".freeze

  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: WORKSPACE_TOKEN)
  end

  test "demo quote has three known lines and totals only the ready line" do
    lines = @quote.quote_lines.to_a

    assert_equal [ 1, 2, 3 ], lines.map(&:position)
    assert_equal %w[ready needs_buyer no_match], lines.map(&:state)
    assert_equal [ BigDecimal("20"), BigDecimal("10"), BigDecimal("2") ], lines.map(&:quantity)
    assert_equal BigDecimal("232.00"), lines.first.unit_price
    assert_nil lines.second.unit_price
    assert_nil lines.third.unit_price

    assert_kind_of BigDecimal, @quote.subtotal
    assert_equal BigDecimal("4640.00"), @quote.subtotal
    assert_equal BigDecimal("4640.00"), lines.first.line_total
    assert_equal 1, @quote.ready_count
    assert_equal 2, @quote.held_count
    assert @quote.sample_data?
    assert_equal "Northline Fabrication", @quote.buyer_name
    refute @quote.awaiting_processing?
    refute @quote.approved?
  end

  test "demo benchmark is labeled as sample data" do
    ready_line = @quote.quote_lines.first

    assert ready_line.sample_benchmark?
    assert_equal "sample", ready_line.benchmark["kind"]
    assert_match(/sample/i, ready_line.price_source)
  end

  test "reference is derived from the record id without a stored column" do
    assert_equal format("RFQ-%04d", @quote.id), @quote.reference
    assert_match(/\ARFQ-\d{4,}\z/, @quote.reference)
    assert_nil Quote.new.reference
    refute_includes Quote.column_names, "reference"
  end

  test "a price on a held line is excluded from the subtotal" do
    held_line = @quote.quote_lines.second
    assert held_line.apply_manual_edit("unit_price" => "999.99")

    @quote.reload
    held_line = @quote.quote_lines.second
    assert_equal BigDecimal("999.99"), held_line.unit_price
    assert held_line.rep_entered_price?
    refute held_line.quotable?
    assert_nil held_line.line_total
    assert_equal BigDecimal("4640.00"), @quote.subtotal
    assert_equal 1, @quote.ready_count
  end

  test "approval requires a ready line and a question on every held line" do
    assert @quote.approvable?

    @quote.quote_lines.second.update!(clarification_question: nil)
    @quote.reload

    refute @quote.approvable?
    assert_raises(Quote::NotApprovable) { @quote.approve! }
    refute @quote.reload.approved?
  end

  test "a quote awaiting processing cannot be approved" do
    quote = Quote.create!(title: "Pasted RFQ", source_text: "Please quote 10 sheets.", workspace_token: WORKSPACE_TOKEN)

    assert quote.awaiting_processing?
    refute quote.approvable?
    assert_equal BigDecimal("0"), quote.subtotal
  end

  test "any saved line edit invalidates approval" do
    @quote.approve!
    assert @quote.reload.approved?

    ready_line = @quote.quote_lines.first
    assert ready_line.apply_manual_edit("notes" => "Confirm the delivery window.")

    refute @quote.reload.approved?
  end

  test "an unchanged submission does not invalidate approval" do
    @quote.approve!
    ready_line = @quote.quote_lines.first

    assert ready_line.apply_manual_edit("unit_price" => "232.00", "quantity" => "20")
    assert @quote.reload.approved?
  end

  test "intake needs pasted text or a file" do
    quote = Quote.new(title: "Empty", workspace_token: WORKSPACE_TOKEN)

    refute quote.valid?
    assert quote.errors[:source_text].any?
  end

  test "stored file bytes are capped at 10 MB" do
    oversized = ("a" * (Quote::MAXIMUM_SOURCE_BYTES + 1)).b
    quote = Quote.new(title: "Large", workspace_token: WORKSPACE_TOKEN, original_filename: "large.pdf", source_bytes: oversized)

    refute quote.valid?
    assert quote.errors[:source_bytes].any?
  end

  test "pasted text is capped at 50,000 characters" do
    quote = Quote.new(title: "Long", workspace_token: WORKSPACE_TOKEN, source_text: "a" * 50_001)

    refute quote.valid?
    assert quote.errors[:source_text].any?
  end

  test "file bytes round trip as binary" do
    bytes = "%PDF-1.4\x00\xFF\xFE binary".b
    quote = Quote.create!(title: "Binary", workspace_token: WORKSPACE_TOKEN, original_filename: "rfq.pdf", source_bytes: bytes)

    assert_equal bytes, quote.reload.source_bytes.b
  end

  test "workspace scope excludes other workspaces" do
    other_quote = QuoteWorkspace::Demo.create!(workspace_token: "another-workspace")

    assert_includes Quote.for_workspace(WORKSPACE_TOKEN), @quote
    refute_includes Quote.for_workspace(WORKSPACE_TOKEN), other_quote
    assert_empty Quote.for_workspace(nil)
  end

  test "filenames are sanitized before storage" do
    assert_equal "evil.pdf", Quote.sanitize_filename("../../etc/evil.pdf")
    assert_equal "rfq.xlsx", Quote.sanitize_filename("C:\\Users\\buyer\\rfq.xlsx")
    assert_equal "a_b_.pdf", Quote.sanitize_filename("a<b>.pdf")
    assert_equal "upload", Quote.sanitize_filename("...")
  end
end
