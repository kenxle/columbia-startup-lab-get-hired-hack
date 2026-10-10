require "test_helper"

# Results follow DistributorPricing::Engine#price_line's output shape.
class CatalogMatch::PricingHandoffTest < ActiveSupport::TestCase
  setup do
    client = Client.create!(name: "Acme Fabrication", workspace_token: "t" * 43)
    @quote = Quote.create!(title: "Acme RFQ", source_text: "see lines", workspace_token: "t" * 43)
    request = CatalogMatch::Suggest.call(client: client, description: "40,000 lb S-330 steel shot")
    @line = CatalogMatch::Approve.call(match_request: request, part_numbers: [ "RC-STEELSHOT-S330" ], quote: @quote)[:lines].first
  end

  def ready_result(overrides = {})
    {
      "part_number" => "RC-STEELSHOT-S330", "status" => "ready", "unit_price" => "0.46", "line_total" => "18400.00",
      "currency" => "USD", "price_scope" => "delivered_ex_tax", "calculated_at" => 1.minute.ago.iso8601,
      "quote_valid_until" => 1.day.from_now.iso8601,
      "selected_offer" => { "supplier" => "Supplier A", "id" => "offer-1" },
      "pricing_analysis" => { "independent_benchmark_suppliers" => 2, "market_low_unit_price" => "0.44",
                              "market_median_unit_price" => "0.47", "market_high_unit_price" => "0.50",
                              "comparison_basis" => "At or below the median of independent delivered supplier quotes, excluding tax; not a claim to be cheapest." },
      "reasons" => [], "buyer_questions" => []
    }.merge(overrides)
  end

  test "the request gives pricing the approved item, quantity and unit" do
    request = CatalogMatch::PricingHandoff.request_for(@line)
    assert_equal "RC-STEELSHOT-S330", request["item"]["part_number"]
    assert_equal "40000", request["quantity"]
    assert_equal "lb", request["unit"]
  end

  test "a ready result makes the line Ready with its benchmark" do
    line = CatalogMatch::PricingHandoff.apply(line: @line, result: ready_result).reload
    assert_equal "ready", line.state
    assert_equal BigDecimal("0.46"), line.unit_price
    assert line.quotable?
    assert_match(/Supplier A/, line.price_source)
    assert_equal "market", line.benchmark["kind"]
    assert_match(/median 0.47/, line.benchmark["explanation"])
  end

  test "an expired or priceless ready result keeps the line held" do
    [ ready_result("quote_valid_until" => 1.minute.ago.iso8601), ready_result("unit_price" => nil),
      ready_result("currency" => nil) ].each do |result|
      line = CatalogMatch::PricingHandoff.apply(line: @line, result: result).reload
      assert_not line.quotable?, result.inspect
      assert_includes line.unresolved_fields, "unit_price"
    end
  end

  test "a held result keeps its reasons and the buyer question" do
    line = CatalogMatch::PricingHandoff.apply(line: @line, result: ready_result(
      "status" => "needs_buyer", "unit_price" => nil, "reasons" => [ "Provide the destination country and postal code." ],
      "buyer_questions" => [ "Provide the destination country and postal code." ]
    )).reload
    assert_not line.quotable?
    assert_match(/Pricing needs the buyer: Provide the destination/, line.notes)
    assert_equal "Provide the destination country and postal code.", line.clarification_question
  end

  test "a result for a different part is refused" do
    assert_raises(CatalogMatch::PricingHandoff::Invalid) do
      CatalogMatch::PricingHandoff.apply(line: @line, result: ready_result("part_number" => "RC-STEELSHOT-S390"))
    end
    assert_nil @line.reload.unit_price
  end

  test "pricing clears an earlier quote approval" do
    @quote.update_columns(approved_at: Time.current)
    CatalogMatch::PricingHandoff.apply(line: @line, result: ready_result)
    assert_not @quote.reload.approved?
  end
end
