require "test_helper"

class QuotesHelperTest < ActionView::TestCase
  include QuotesHelper

  test "evidence does not highlight fragments inside unrelated words" do
    result = highlighted_source("SS sheet; stainless steel", ["SS"])
    fragment = Nokogiri::HTML.fragment(result)
    assert_equal ["SS"], fragment.css("mark").map(&:text)
  end

  test "unit prices retain sub-cent precision while totals remain currency values" do
    assert_equal "USD 232.0050", display_money(BigDecimal("232.005"))
    assert_equal "USD 4,640.10", display_money(BigDecimal("4640.10"))
  end

  test "source HTML is escaped" do
    result = highlighted_source('<script>alert(1)</script> SS', ["SS"])
    fragment = Nokogiri::HTML.fragment(result)
    assert_empty fragment.css("script")
    assert_includes fragment.text, "<script>"
  end

  test "line context takes priority over generic field words" do
    line = QuoteLine.new(original_text: "1. SS sheet qty 20", evidence: {"material" => {"text" => "SS"}},
      compliance: [{"label" => "MTR", "evidence" => "MTR required"}])
    assert_equal ["1. SS sheet qty 20", "MTR required"], evidence_phrases(line)
  end
end
