require "test_helper"

class QuoteWorkspaceApplyResultTest < ActiveSupport::TestCase
  setup do
    @quote = Quote.create!(
      title: "Pasted RFQ",
      buyer_name: "Northline Fabrication",
      source_text: QuoteWorkspace::Demo::SOURCE_TEXT,
      workspace_token: "apply-result-test-workspace"
    )
  end

  def demo_result
    QuoteWorkspace::Demo.result
  end

  def apply(result)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
  end

  def assert_rejected(result, message_pattern)
    error = assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    assert_match message_pattern, error.message
    error
  end

  test "a valid result replaces the lines and sets sample labeling" do
    apply(demo_result)
    @quote.reload

    assert_equal 3, @quote.quote_lines.count
    assert @quote.sample_data?
    assert_equal BigDecimal("4640.00"), @quote.subtotal
  end

  test "applying a new result clears an earlier approval" do
    apply(demo_result)
    @quote.approve!

    apply(demo_result)

    refute @quote.reload.approved?
  end

  test "unknown fields are discarded" do
    result = demo_result
    result["provider_trace"] = { "tokens" => 1234 }
    ready_line = result["lines"].first
    ready_line["id"] = 999_999
    ready_line["quote_id"] = 0
    ready_line["confidence"] = 0.99
    ready_line["edited_fields"] = [ "material" ]
    ready_line["spec"]["color"] = "blue"
    ready_line["evidence"]["color"] = { "text" => "blue" }
    ready_line["evidence"]["grade"]["model_reasoning"] = "hidden"
    ready_line["benchmark"]["internal_cost"] = "100.00"
    ready_line["compliance"].first["certified"] = true

    apply(result)
    line = @quote.reload.quote_lines.first

    refute_equal 999_999, line.id
    assert_equal @quote.id, line.quote_id
    assert_equal [], line.edited_fields
    refute line.spec.key?("color")
    refute line.evidence.key?("color")
    assert_equal %w[text location explanation], line.evidence["grade"].keys
    refute line.benchmark.key?("internal_cost")
    refute line.compliance.first.key?("certified")
    refute line.respond_to?(:confidence)
  end

  test "a line missing evidence for a spec value is rejected" do
    result = demo_result
    result["lines"].first["evidence"].delete("grade")

    assert_rejected(result, /missing source evidence for grade/)
    assert @quote.reload.awaiting_processing?
  end

  test "a line missing evidence for its quantity is rejected" do
    result = demo_result
    result["lines"].second["evidence"].delete("quantity")

    assert_rejected(result, /missing source evidence for quantity/)
  end

  test "evidence without quoted source text is rejected" do
    result = demo_result
    result["lines"].first["evidence"]["material"] = { "text" => "  ", "location" => "item 1" }

    assert_rejected(result, /evidence for material must quote the source text/)
  end

  test "a ready flag is not trusted without catalog SKU, price, source and benchmark" do
    { "catalog_sku" => /without a catalog SKU/,
      "unit_price" => /without a unit price/,
      "price_source" => /without a price source/,
      "benchmark" => /without a named benchmark/ }.each do |field_name, message_pattern|
      result = demo_result
      result["lines"].first[field_name] = nil
      assert_rejected(result, message_pattern)
    end
  end

  test "a ready line with unresolved fields is rejected" do
    result = demo_result
    result["lines"].first["unresolved_fields"] = [ "grade" ]

    assert_rejected(result, /Ready with unresolved fields/)
  end

  test "unknown states and missing buyer questions are rejected" do
    result = demo_result
    result["lines"].first["state"] = "approved"
    assert_rejected(result, /unknown state/)

    result = demo_result
    result["lines"].second["clarification_question"] = ""
    assert_rejected(result, /no clarification question/)

    result = demo_result
    result["lines"].third["catalog_sku"] = "SAMPLE-ANY"
    assert_rejected(result, /No match but names a catalog SKU/)
  end

  test "invalid quantities and prices are rejected" do
    [ "abc", "-5", "1e3", 12.5e-9 ].each do |bad_quantity|
      result = demo_result
      result["lines"].first["quantity"] = bad_quantity
      assert_rejected(result, /quantity must be a nonnegative decimal number/)
    end

    result = demo_result
    result["lines"].first["quantity"] = "0"
    assert_rejected(result, /positive quantity/)

    result = demo_result
    result["lines"].first["unit_price"] = "-232.00"
    assert_rejected(result, /unit_price must be a nonnegative decimal number/)
  end

  test "schema version, sample flag, positions and line list are checked" do
    result = demo_result
    result["schema_version"] = 2
    assert_rejected(result, /schema_version must be 1/)

    result = demo_result
    result["sample_data"] = "yes"
    assert_rejected(result, /sample_data must be true or false/)

    result = demo_result
    result["lines"].second["position"] = 1
    assert_rejected(result, /positions must be unique/)

    result = demo_result
    result["lines"] = []
    assert_rejected(result, /non-empty list/)

    assert_rejected("not a hash", /must be a hash/)
  end

  test "a rejected result leaves existing lines and approval untouched" do
    apply(demo_result)
    @quote.approve!
    original_line_ids = @quote.reload.quote_lines.map(&:id)

    result = demo_result
    result["sample_data"] = false
    result["lines"].third["evidence"].delete("length")
    assert_rejected(result, /missing source evidence for length/)

    @quote.reload
    assert_equal original_line_ids, @quote.quote_lines.map(&:id)
    assert @quote.sample_data?
    assert @quote.approved?
  end

  test "a model failure partway through rolls back the whole import" do
    apply(demo_result)
    @quote.approve!
    original_line_ids = @quote.reload.quote_lines.map(&:id)

    result = demo_result
    result["sample_data"] = false
    # Passes the result checks but fails the model length validation, so the
    # first line is written before the second line fails.
    result["lines"].second["description"] = "x" * 600

    assert_rejected(result, /Description is too long/)

    @quote.reload
    assert_equal original_line_ids, @quote.quote_lines.map(&:id)
    assert_equal 3, @quote.quote_lines.count
    assert @quote.sample_data?
    assert @quote.approved?
    assert_equal BigDecimal("4640.00"), @quote.subtotal
  end

  test "string keys and symbol keys produce the same lines" do
    apply(demo_result.deep_symbolize_keys)

    assert_equal 3, @quote.reload.quote_lines.count
  end
  test "evidenced internal holds import beside ready lines without buyer questions" do
    result = demo_result
    price_hold = result["lines"].second
    price_hold.merge!("clarification_question" => nil, "catalog_sku" => "KNOWN", "unit_price" => nil,
      "unresolved_fields" => ["unit_price"], "processing" => {"match" => {"status" => "exact"}})
    result["lines"].third.merge!("clarification_question" => nil,
      "processing" => {"match" => {"status" => "no_match", "reason" => "Unsupported screw"}})
    apply(result)
    assert @quote.reload.approvable?
    assert_equal BigDecimal("4640"), @quote.subtotal
    @quote.quote_lines.drop(1).each do |line|
      assert_nil line.unit_price
      assert_nil line.line_total
      assert @quote.internal_hold?(line)
    end
    result["lines"].shift
    apply(result)
    refute @quote.reload.approvable?
    assert_raises(Quote::NotApprovable) { @quote.approve! }
  end

  test "blank questions without matching internal hold evidence still roll back" do
    apply(demo_result)
    @quote.approve!
    before = @quote.quote_lines.map(&:attributes)
    ["needs_buyer", "no_match"].each do |state|
      result = demo_result
      result["lines"].second.merge!("state" => state, "clarification_question" => nil,
        "catalog_sku" => nil, "processing" => {"match" => {"status" => "ambiguous"}})
      assert_rejected(result, /no clarification question/)
      assert_equal before, @quote.reload.quote_lines.map(&:attributes)
      assert @quote.approved?
    end
  end

end
