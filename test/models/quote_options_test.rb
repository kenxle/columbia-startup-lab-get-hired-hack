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

  test "processing price bases and ISO observations retain their source evidence" do
    [["lb", "USD per lb"], ["each", "USD each"], ["ea", "USD each"], ["sheet", "USD per sheet"]].each do |unit, basis|
      @line.quantity_unit = @option["quantity_unit"] = unit
      @option["benchmark"]["unit"] = basis
      ["2026-10-10", "2026-10-10T17:04:39Z", "2026-10-10T13:04:39.123-04:00"].each do |stamp|
        @option["benchmark"]["as_of"] = stamp
        actual = options.first
        assert actual[:priced], "#{basis} at #{stamp}"
        assert_equal "2.1234", actual[:unit_price]
        assert_equal "21.23", actual[:total]
        assert_equal stamp, actual[:benchmark]["as_of"]
        assert_equal basis, actual[:benchmark]["unit"]
      end
    end
  end

  test "processing payloads retain all price safety checks" do
    @line.quantity_unit = @option["quantity_unit"] = "lb"
    @option["benchmark"].merge!("unit" => "USD per lb", "as_of" => "2026-10-10T17:04:39Z")
    changes = [
      {"currency" => "EUR"}, {"unresolved_fields" => ["material"]},
      {"benchmark" => {"unit" => "USD per kg"}}, {"benchmark" => {"unit" => "USD each"}},
      {"benchmark" => {"unit" => "EUR per lb"}}
    ]
    ["2026-02-30T17:04:39Z", "2026-10-10T25:04:39Z", "2026-10-10T17:60:39Z",
      "2026-10-10T17:04:39", "2026-10-10T17:04:39+99:00", "2026-10-10garbage"].each do |stamp|
      changes << {"benchmark" => {"as_of" => stamp}}
    end
    changes.each do |change|
      original = @option
      @option = original.deep_merge(change)
      assert options.none? { |entry| entry[:priced] }, change.inspect
      @option = original
    end
  end
end
