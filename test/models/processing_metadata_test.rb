require "test_helper"

class ProcessingMetadataTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "metadata-test")
  end

  def result_fixture(name = "ready_an3_bolt")
    JSON.parse(Rails.root.join("tools/rfq_processing/spec/fixtures/results/#{name}.json").read)
  end

  def apply(result)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
  end

  test "all three Yuval fixtures retain processing metadata and normalized hardware evidence" do
    %w[ready_an3_bolt needs_buyer_an3_missing_length no_match_304_sheet].each do |name|
      result = result_fixture(name)
      source = result["lines"].first
      apply(result)
      line = @quote.reload.quote_lines.first

      assert_equal result["revision"], @quote.processing_revision
      assert_equal source["line_id"], line.line_id
      assert_equal source["processing"], line.processing
      assert_equal source["state"], line.state
      assert_equal source["evidence"], line.evidence
      source["spec"].compact.each { |key, value| assert_equal value.to_s, line.spec[key] }
      assert_equal source["state"] == "ready", line.quotable?
      assert_nil line.line_total unless line.quotable?
    end
  end

  test "omitted and nil extensions clear the previous processing revision" do
    [false, true].each do |explicit_nil|
      apply(result_fixture)
      result = QuoteWorkspace::Demo.result
      if explicit_nil
        result["revision"] = nil
        result["lines"].each { |line| line.merge!("line_id" => nil, "processing" => nil) }
      end
      apply(result)

      assert_nil @quote.reload.processing_revision
      @quote.quote_lines.each do |line|
        assert_nil line.line_id
        assert_nil line.processing
      end
    end
  end

  test "symbol-keyed processing payloads remain supported" do
    result = result_fixture
    apply(result.deep_symbolize_keys)

    assert_equal result["revision"], @quote.reload.processing_revision
    assert_equal result["lines"].first["processing"], @quote.quote_lines.first.processing
  end

  test "revision and line ids reject blank and wrong types" do
    [[], "", {"id" => ""}, {"id" => 1}, {"id" => "x" * 201}].each do |revision|
      result = result_fixture
      result["revision"] = revision
      assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    end
    ["", " ", 123, [], "x" * 201].each do |identifier|
      result = result_fixture
      result["lines"].first["line_id"] = identifier
      assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    end
  end

  test "conflicting string and symbol keys cannot bypass metadata validation" do
    apply(result_fixture)
    @quote.approve!
    before_quote = @quote.reload.attributes
    before_lines = @quote.quote_lines.map(&:attributes)
    result = result_fixture
    result[:revision] = { id: "" }
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }

    result = result_fixture
    result["revision"][:id] = ""
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }

    result = result_fixture
    cycle = {}
    cycle["self"] = cycle
    result["lines"].first[:processing] = cycle
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    assert_equal before_quote, @quote.reload.attributes
    assert_equal before_lines, @quote.quote_lines.map(&:attributes)
  end

  test "processing metadata rejects non JSON types excessive depth size and node counts" do
    cycle = {}
    cycle["self"] = cycle
    invalid_metadata = [
      [], "text", {"bad" => Object.new}, {"bad" => Float::NAN},
      {"bad" => Float::INFINITY}, {"bad" => :symbol},
      {"large" => "x" * 32_769}, {"many" => Array.new(1_001, 1)},
      {"deep" => 10.times.reduce({}) { |child, _| {"nested" => child} }},
      cycle
    ]
    invalid_metadata.each do |metadata|
      result = result_fixture
      result["lines"].first["processing"] = metadata
      assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    end
    result = result_fixture
    result["revision"]["unsafe"] = Object.new
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
  end

  test "duplicate line ids are rejected before replacing existing lines" do
    apply(result_fixture)
    before = @quote.reload.quote_lines.map(&:attributes)
    result = result_fixture
    second_line = result["lines"].first.deep_dup
    second_line["position"] = 2
    result["lines"] << second_line

    error = assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    assert_match(/line_id must be unique/, error.message)
    assert_equal before, @quote.reload.quote_lines.map(&:attributes)
  end

  test "model errors partway through import roll back revision lines metadata and approval" do
    apply(result_fixture)
    @quote.approve!
    before_quote = @quote.reload.attributes
    before_lines = @quote.quote_lines.map(&:attributes)
    result = result_fixture("needs_buyer_an3_missing_length")
    second_line = result["lines"].first.deep_dup
    second_line.merge!("position" => 2, "line_id" => "different-id", "description" => "x" * 501)
    result["lines"] << second_line

    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    assert_equal before_quote, @quote.reload.attributes
    assert_equal before_lines, @quote.quote_lines.map(&:attributes)
  end

  test "metadata never makes held lines ready or grants quote approval" do
    result = result_fixture("needs_buyer_an3_missing_length")
    result["revision"]["approved_at"] = Time.current.iso8601
    result["lines"].first["processing"].merge!("state" => "ready", "approved" => true, "confidence" => 1.0)
    apply(result)

    refute @quote.reload.approved?
    refute @quote.approvable?
    refute @quote.quote_lines.first.quotable?
    assert_nil @quote.quote_lines.first.line_total
    result["lines"].first["state"] = "ready"
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
  end

  test "each rep hardware edit holds the line and invalidates approval" do
    %w[part_number diameter thread grip drilling].each do |field|
      apply(result_fixture)
      @quote.approve!
      line = @quote.quote_lines.first

      assert line.apply_manual_edit("spec" => {field => "changed"})
      refute @quote.reload.approved?
      assert_equal "needs_buyer", line.reload.state
      assert_includes line.edited_fields, field
      assert_nil line.line_total
    end
  end

  test "hardware specs require source evidence" do
    result = result_fixture
    result["lines"].first["evidence"].delete("part_number")

    error = assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    assert_match(/missing source evidence for part_number/, error.message)
  end

  test "direct model validation rejects invalid extensions and duplicate ids within a quote" do
    apply(result_fixture)
    line = @quote.quote_lines.first
    line.line_id = 123
    refute line.valid?
    line.reload
    line.processing = []
    refute line.valid?
    line.reload
    duplicate = line.dup
    duplicate.position = 2
    refute duplicate.valid?
    assert duplicate.errors[:line_id].any?
    duplicate.quote = QuoteWorkspace::Demo.create!(workspace_token: "another-quote")
    duplicate.position = 4
    assert duplicate.valid?

    @quote.processing_revision = {"id" => ""}
    refute @quote.valid?
  end
end
