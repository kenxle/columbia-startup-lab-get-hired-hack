require "test_helper"

class QuoteLineLeadTimeTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "lead-time-test")
    @line = @quote.quote_lines.first
  end

  def apply(result)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
  end

  def add_timing(line = @line)
    line.update!(lead_time: "5 working days after confirmation", lead_time_source: "Supplier confirmation, 2026-10-10")
  end

  test "unknown timing does not prevent readiness or imply availability" do
    assert @line.quotable?
    assert_nil @line.lead_time
    assert_equal "to confirm", @line.display_lead_time
    refute @line.sourced_lead_time?
    assert @quote.approvable?
  end

  test "only quotable lines with sourced timing show a lead time" do
    add_timing
    assert_equal "5 working days after confirmation", @line.display_lead_time
    assert @line.sourced_lead_time?
    held = @quote.quote_lines.second
    add_timing(held)
    assert_equal "to confirm", held.display_lead_time
    refute held.sourced_lead_time?
    assert_nil held.line_total

    @line.lead_time_source = nil
    assert_equal "to confirm", @line.display_lead_time
  end

  test "timing fields require bounded text and a source for a nonblank promise" do
    @line.lead_time = "5 days"
    refute @line.valid?
    assert @line.errors[:lead_time_source].any?
    @line.lead_time_source = "Supplier quote"
    assert @line.valid?
    %w[lead_time lead_time_source].each do |field|
      [123, [], "x" * 201].each do |invalid|
        @line.reload
        add_timing
        @line[field] = invalid
        refute @line.valid?, "#{field} should reject #{invalid.class}"
      end
    end
  end

  test "processing imports timing but old or nil payloads clear it" do
    [false, true].each do |explicit_nil|
      result = QuoteWorkspace::Demo.result
      result["lines"].first.merge!("lead_time" => "  5 days  ", "lead_time_source" => "  Supplier quote  ")
      apply(result)
      assert_equal "5 days", @quote.reload.quote_lines.first.display_lead_time
      assert_equal "Supplier quote", @quote.quote_lines.first.lead_time_source

      old_result = QuoteWorkspace::Demo.result
      old_result["lines"].first.merge!("lead_time" => nil, "lead_time_source" => nil) if explicit_nil
      apply(old_result)
      line = @quote.reload.quote_lines.first
      assert_nil line.lead_time
      assert_nil line.lead_time_source
      assert_equal "to confirm", line.display_lead_time
    end
  end

  test "invalid timing import rolls back earlier rows and preserves approval" do
    add_timing
    @quote.approve!
    original_lines = @quote.reload.quote_lines.map(&:attributes)
    original_revision = @quote.review_revision
    [
      {"lead_time" => "5 days"},
      {"lead_time" => "x" * 201, "lead_time_source" => "Supplier quote"},
      {"lead_time" => "5 days", "lead_time_source" => "x" * 201},
      {"lead_time" => 5, "lead_time_source" => "Supplier quote"}
    ].each do |invalid|
      result = QuoteWorkspace::Demo.result
      result["lines"].second.merge!(invalid)

      assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
      assert_equal original_lines, @quote.reload.quote_lines.map(&:attributes)
      assert @quote.approved?
      assert_equal original_revision, @quote.review_revision
    end
  end

  test "spec quantity and unit edits clear stale timing and invalidate approval" do
    [
      {"spec" => {"grade" => "316"}},
      {"quantity" => "25"},
      {"quantity_unit" => "piece"}
    ].each do |edit|
      apply(QuoteWorkspace::Demo.result)
      @line = @quote.reload.quote_lines.first
      add_timing
      @quote.approve!
      assert @line.apply_manual_edit(edit)

      @line.reload
      assert_nil @line.lead_time
      assert_nil @line.lead_time_source
      assert_equal "to confirm", @line.display_lead_time
      assert_nil @line.line_total
      refute @quote.reload.approved?
    end
  end

  test "failed spec edits preserve stored timing and non-spec edits keep sourced timing" do
    add_timing
    refute @line.apply_manual_edit("quantity" => "invalid")
    assert_equal "5 working days after confirmation", @line.reload.display_lead_time
    assert @line.apply_manual_edit("notes" => "Confirm packaging.")
    assert_equal "5 working days after confirmation", @line.reload.display_lead_time
    assert @line.apply_manual_edit("unit_price" => "240")
    assert_equal "5 working days after confirmation", @line.reload.display_lead_time
  end

  test "nested stocked timing with source reaches display email PDF snapshot and CSV" do
    result = nested_timing_result
    apply(result)
    line = @quote.reload.quote_lines.first
    assert_equal "24 to 48 hours", line.display_lead_time
    assert_equal "RudCo catalog stock confirmation", line.lead_time_source
    @quote.approve!
    assert_includes QuoteWorkspace::CsvExport.new(@quote).to_csv, '"24 to 48 hours","RudCo catalog stock confirmation"'
    assert_includes QuoteWorkspace::FinalQuote.new(@quote).body, "Lead time: 24 to 48 hours"
    QuoteWorkspace::FinalQuote.new(@quote).with_snapshot do |snapshot|
      assert_equal "24 to 48 hours", snapshot[:lines].first[:lead_time]
    end
  end

  test "nested timing does not infer stock from unknown or held lines" do
    result = nested_timing_result
    result["lines"].first["processing"]["lead_time"]["stocked"] = false
    result["lines"].second["processing"] = nested_timing_result["lines"].first["processing"]
    apply(result)
    @quote.reload.quote_lines.first(2).each do |line|
      assert_nil line.lead_time
      assert_nil line.lead_time_source
      assert_equal "to confirm", line.display_lead_time
    end
  end

  test "third party source or candidate stock scope never establishes RudCo timing" do
    [ "positive stock at a dealer warehouse", "third-party stock", "supplier inventory", "synthetic catalog", "stock unconfirmed" ].each do |source|
      result = nested_timing_result
      result["lines"].first["processing"]["lead_time"]["source"] = source
      apply(result)
      assert_equal "to confirm", @quote.reload.quote_lines.first.display_lead_time
    end
    [ { "stock_scope" => "positive stock at a dealer warehouse" }, { "stock_reported" => false }, { "catalog_provenance" => "sample inventory" } ].each do |stock|
      result = nested_timing_result
      first = result["lines"].first
      first["processing"]["match"] = { "candidates" => [ { "item_id" => first["catalog_sku"], "stock" => stock } ] }
      apply(result)
      assert_equal "to confirm", @quote.reload.quote_lines.first.display_lead_time
    end
  end

  test "malformed or unsourced nested timing rejects atomically" do
    @quote.approve!
    originals = @quote.quote_lines.map(&:attributes)
    original_revision = @quote.review_revision
    [ false, "soon", { "text" => "24 hours", "stocked" => "true", "source" => "RudCo" },
      { "text" => "24 hours", "stocked" => true, "source" => " " },
      { "text" => "24 hours", "stocked" => true, "source" => "x" * 201 },
      { "text" => "24 hours", "stocked" => true, "source" => "RudCo", "unknown" => true } ].each do |timing|
      result = nested_timing_result
      result["lines"].first["processing"]["lead_time"] = timing
      assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
      assert_equal originals, @quote.reload.quote_lines.map(&:attributes)
      assert_equal original_revision, @quote.review_revision
      assert @quote.approved?
    end
  end

  test "explicit schema one timing or explicit nulls take precedence over nested timing" do
    result = nested_timing_result
    result["lines"].first.merge!("lead_time" => "5 days", "lead_time_source" => "Supplier confirmation")
    apply(result)
    assert_equal "5 days", @quote.reload.quote_lines.first.display_lead_time
    result["lines"].first.merge!("lead_time" => nil, "lead_time_source" => nil)
    apply(result)
    assert_equal "to confirm", @quote.reload.quote_lines.first.display_lead_time
  end

  def nested_timing_result
    result = QuoteWorkspace::Demo.result
    result["lines"].first["processing"] = {
      "lead_time" => { "text" => "24 to 48 hours", "stocked" => true, "source" => "RudCo catalog stock confirmation" }
    }
    result
  end

  test "CSV includes safe timing and source and hides held timing" do
    @line.update!(lead_time: "=5+5", lead_time_source: "@supplier")
    held = @quote.quote_lines.second
    held.update!(lead_time: "Hidden stale timing", lead_time_source: "Hidden stale source")
    @quote.approve!
    csv = QuoteWorkspace::CsvExport.new(@quote.reload).to_csv

    assert_includes csv, '"Lead time","Lead time source"'
    assert_includes csv, %("'=5+5","'@supplier")
    refute_includes csv, "Hidden stale timing"
    refute_includes csv, "Hidden stale source"
    assert_includes csv, '"to confirm",""'
    assert_includes csv, '"232.00","4640.00"'
  end
end
