require "test_helper"

class QuoteOptionsTest < ActiveSupport::TestCase
  def setup
    @option = {
      "id" => "line-1-o1", "label" => "Option A: 2B finish", "catalog_sku" => "SS-2B",
      "spec" => { "material" => "stainless steel", "thickness_in" => 0.0625, "finish" => "2B" },
      "quantity" => 10, "quantity_unit" => "sheet", "unit_price" => "2.1234", "currency" => "USD",
      "price_source" => "Observed listing", "benchmark" => { "name" => "Listing", "as_of" => "2026-10-10", "kind" => "list_price", "unit" => "sheet" },
      "unresolved_fields" => [], "lead_time" => "To confirm", "lead_time_source" => "No stock confirmation"
    }
    @line = QuoteLine.new(state: "needs_buyer", quantity: 10, quantity_unit: "sheet", edited_fields: [])
  end

  def options
    @line.processing = { "alternates" => [@option, @option.merge("id" => "line-1-o2", "label" => "Option B: No. 4 finish")] }
    QuoteWorkspace::QuoteOptions.for(@line)
  end

  test "canonical options retain their own precise price and flat lead time source" do
    actual = options
    assert_equal "Option A: 2B finish", actual.first[:label]
    assert_equal "2.1234", actual.first[:unit_price]
    assert_equal "21.23", actual.first[:total]
    assert_equal "No stock confirmation", actual.first[:lead_time_source]
    assert_nil @line.line_total
  end

  test "malformed or incomparable prices never become quotable options" do
    [ {"unit_price" => "NaN"}, {"unit_price" => "-1"}, {"currency" => "EUR"},
      {"unresolved_fields" => ["standard"]}, {"benchmark" => @option["benchmark"].merge("unit" => "lb")},
      {"benchmark" => @option["benchmark"].merge("as_of" => "2026-02-30")}, {"price_source" => ""} ].each do |change|
      original = @option
      @option = original.deep_merge(change)
      actual = options
      assert_equal 2, actual.size
      assert actual.none? { |entry| entry[:priced] }
      assert actual.all? { |entry| entry[:unit_price].nil? && entry[:total].nil? }
      @option = original
    end
  end

  test "quantity mismatch and stale rep edits suppress alternatives" do
    @option["quantity"] = 20
    assert_empty options
    @option["quantity"] = 10
    @line.edited_fields = ["quantity"]
    assert_empty options
    @line.edited_fields = []
    @line.state = "no_match"
    assert_empty options
  end
end
