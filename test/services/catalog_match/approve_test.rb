require "test_helper"

class CatalogMatch::ApproveTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: "Acme Fabrication", workspace_token: "t" * 43)
    @quote = Quote.create!(title: "Acme RFQ", source_text: "see lines", workspace_token: "t" * 43)
    @request = CatalogMatch::Suggest.call(client: @client, description: "304 SS sheet 16ga 4x8 x25")
  end

  test "an approved item becomes a held RFQ line with the PN, spec and the buyer's words" do
    result = CatalogMatch::Approve.call(match_request: @request, part_numbers: [ "RC-SS304-SHT-16GA-48X96-2B" ], quote: @quote)
    line = result[:lines].first.reload

    assert_equal "RC-SS304-SHT-16GA-48X96-2B", line.catalog_sku
    assert_equal 25, line.quantity
    assert_equal "stainless steel", line.spec["material"]
    assert_equal "2B", line.spec["finish"]
    assert_equal "16ga", line.evidence["thickness"]["text"]
    assert_equal [ "unit_price" ], line.unresolved_fields
    assert_not line.quotable?, "no price yet, so it must not count as Ready"
    assert @request.reload.approved?
    assert_equal @quote.id, @request.quote_id
  end

  test "approving several items adds a line for each" do
    CatalogMatch::Approve.call(match_request: @request, quote: @quote,
                               part_numbers: %w[RC-SS304-SHT-16GA-48X96-2B RC-SS304-SHT-16GA-48X96-4])
    assert_equal 2, @quote.quote_lines.count
    assert_equal [ 1, 2 ], @quote.quote_lines.pluck(:position)
  end

  test "approval clears an earlier quote approval" do
    @quote.update_columns(approved_at: Time.current)
    CatalogMatch::Approve.call(match_request: @request, part_numbers: [ "RC-SS304-SHT-16GA-48X96-2B" ], quote: @quote)
    assert_not @quote.reload.approved?
  end

  test "only suggested items can be approved" do
    error = assert_raises(CatalogMatch::Approve::Invalid) do
      CatalogMatch::Approve.call(match_request: @request, part_numbers: [ "RC-A36-PLT-500-60X120" ], quote: @quote)
    end
    assert_match(/not suggested/, error.message)
    assert_equal 0, @quote.quote_lines.count
  end
end
