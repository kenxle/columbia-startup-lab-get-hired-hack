require "test_helper"

class FinalQuoteTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "final-quote")
    @quote.approve!
    @draft = QuoteWorkspace::FinalQuote.new(@quote)
  end

  test "email draft labels sample and concept data without claiming sending or attachments" do
    assert_equal "Quote #{@quote.reference}", @draft.subject
    assert_equal "#{@quote.reference}-quote-SAMPLE-email-draft.txt", @draft.filename
    body = @draft.body
    [ "Draft, not sent", "Concept quote", "SAMPLE DATA", "USD 4640.00", "Files are not attached", "no email has been sent",
      "#{@quote.reference}-quote-SAMPLE.pdf", "#{@quote.reference}-quote-SAMPLE.csv", "Lead time: to confirm", "Mill test report" ].each do |value|
      assert_includes body, value
    end
    @quote.quote_lines.reject(&:quotable?).each { |line| assert_includes body, line.clarification_question }
  end

  test "local email preview describes its actual attachments" do
    body = @draft.body(attachments_included: true)
    assert_includes body, "Attached to this local preview:"
    assert_includes body, "No email has been sent to the buyer."
    refute_includes body, "Files are not attached"
  end

  test "unapproved and invalid quotes refuse every exposed draft action" do
    @quote.invalidate_approval!
    %i[subject filename body].each { |method| assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { @draft.public_send(method) } }
    @quote.approve!
    @quote.quote_lines.second.update_columns(clarification_question: nil)
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { @draft.body }
  end

  test "stale object and loaded associations cannot export a subsequently edited quote" do
    @quote.quote_lines.load
    other = Quote.find(@quote.id)
    other.quote_lines.first.apply_manual_edit("notes" => "Updated after approval")
    assert @quote.approved?
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { @draft.body }
  end

  test "snapshot holds the parent lock and leaves all persisted values unchanged" do
    before_quote = @quote.attributes
    before_lines = @quote.quote_lines.map(&:attributes)
    @draft.with_snapshot do |data|
      assert Quote.connection.transaction_open?
      assert_equal @quote.approved_at.utc.iso8601, data[:approved_at]
      assert_equal [ 1, 2, 3 ], data[:lines].map { |line| line[:position] }
    end
    @draft.body
    assert_equal before_quote, @quote.reload.attributes
    assert_equal before_lines, @quote.quote_lines.map(&:attributes)
  end

  test "buyer presentation excludes notes original source and processing internals" do
    @quote.quote_lines.first.update!(notes: "INTERNAL-NOTE", original_text: "ORIGINAL-PRIVATE-LINE")
    @quote.update!(source_text: "PRIVATE-SOURCE", source_bytes: "PRIVATE-BYTES", original_filename: "PRIVATE-FILENAME.pdf",
      processing_revision: { "id" => "PRIVATE-PROCESSING" })
    text = @draft.body
    %w[INTERNAL-NOTE ORIGINAL-PRIVATE-LINE PRIVATE-SOURCE PRIVATE-BYTES PRIVATE-FILENAME PRIVATE-PROCESSING].each do |value|
      refute_includes text, value
    end
    @quote.quote_lines.first.update!(description: nil)
    @draft.with_snapshot { |data| assert_equal "Line 1", data[:lines].first[:description] }
  end

  test "snapshot retains precise prices hardware specs sourced lead times and requested paperwork" do
    line = @quote.quote_lines.first
    line.update!(unit_price: "1.2345", quantity: "3", spec: line.spec.merge("diameter" => "Ø ¼ in ±0.01", "thread" => "10-32 UNF"),
      lead_time: "3 business days", lead_time_source: "Supplier quote Q-5")
    @draft.with_snapshot do |data|
      row = data[:lines].first
      assert_equal "1.2345", row[:unit_price]
      assert_equal "3.70", row[:total]
      assert_equal "3.70", data[:subtotal]
      assert_includes row[:spec], [ "Diameter", "Ø ¼ in ±0.01" ]
      assert_equal "3 business days", row[:lead_time]
      assert_equal "Supplier quote Q-5", row[:lead_time_source]
      assert_includes row[:compliance], "Mill test report"
      data[:lines].drop(1).each do |held|
        assert_nil held[:sku]
        assert_nil held[:unit_price]
        assert_nil held[:total]
      end
    end
  end

  test "rep price override removes prior benchmark claims" do
    @quote.quote_lines.first.apply_manual_edit("unit_price" => "235")
    @quote.approve!
    @draft.with_snapshot do |data|
      assert data[:lines].first[:rep_price]
      assert_empty data[:lines].first[:benchmark]
      assert_equal "Rep-entered price", data[:lines].first[:price_source]
    end
    refute_includes @draft.body, "Sample price table"
    assert_includes @draft.body, "Rep-entered price. Previous benchmark claims do not apply."
  end

  test "email explains ready prices with benchmark evidence and identifies absent benchmarks" do
    body = @draft.body
    assert_includes body, "Unit price: USD 232.00 | Line total: USD 4640.00"
    assert_includes body, "Benchmark: Sample price table"
    assert_includes body, "As of: 2026-10-10"
    assert_includes body, @quote.quote_lines.first.benchmark["explanation"]
    @quote.quote_lines.first.update!(benchmark: nil)
    assert_includes @draft.body, "Benchmark: not provided"
  end
end
