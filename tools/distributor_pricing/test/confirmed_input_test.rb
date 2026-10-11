require "minitest/autorun"
require_relative "../lib/distributor_pricing/agent"

class DistributorConfirmedInputTest < Minitest::Test
  def setup
    @intake = DistributorPricing::Intake.new
    @text = "S-330 steel shot, lb\nS-170 steel shot, 100 lb"
    @row = { "original_text" => "S-330 steel shot, lb", "part_number" => "S-330",
      "quantity" => "2000", "unit" => "lb", "quote_line_id" => 1,
      "evidence" => { "text" => "2000 lb", "location" => "buyer answer" } }
    @row["part_number"] = @intake.parse(rfq: @text)["lines"][0].dig("item", "part_number")
  end

  def apply(text = @text, input = nil)
    input ||= DistributorPricing::Intake::ConfirmedItems.new(rfq: @text, revision: "current", rows: [@row])
    @intake.apply_confirmed_items(@intake.parse(rfq: text), input, rfq: text)
  end

  def test_preserves_original_and_other_lines
    parsed = @intake.parse(rfq: @text)
    @row["part_number"] = parsed["lines"][0].dig("item", "part_number")
    result = apply
    assert_equal "2000", result["lines"][0]["quantity"]
    assert_equal "S-330 steel shot, lb", result["lines"][0]["original_text"]
    assert_equal parsed["lines"][1], result["lines"][1]
  end

  def test_raw_json_and_changed_original_are_rejected
    assert_raises(ArgumentError) { apply(@text, { "rows" => [@row] }) }
    assert_raises(ArgumentError) { apply(@text + "\nnew request") }
  end

  def test_duplicate_sources_and_conflicting_quantity_are_not_overwritten
    @text = "S-330 steel shot, lb\nS-330 steel shot, lb"
    assert apply["lines"].all? { |line| line["quantity"].nil? }
    @text = @row["original_text"] = "S-330 steel shot, 100 lb"
    @row["part_number"] = @intake.parse(rfq: @text)["lines"][0].dig("item", "part_number")
    assert_equal "100", apply["lines"][0]["quantity"]
  end
end
