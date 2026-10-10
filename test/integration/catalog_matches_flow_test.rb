require "test_helper"

class CatalogMatchesFlowTest < ActionDispatch::IntegrationTest
  test "the rep finds an item for a client, approves it, and it lands on a new RFQ" do
    get catalog_matches_path
    assert_response :success

    post catalog_matches_path, params: { client_name: "Acme Fabrication", description: "304 SS sheet 16ga 4x8 x25" }
    request_record = MatchRequest.last
    assert_redirected_to catalog_match_path(request_record)
    follow_redirect!
    assert_response :success
    assert_select ".match-card", 2
    assert_select ".callout--held", /2B or #4/
    assert_select "svg.item-drawing", 2

    assert_difference -> { QuoteLine.count }, 1 do
      post approve_catalog_match_path(request_record),
           params: { part_numbers: [ "RC-SS304-SHT-16GA-48X96-4" ], quote_id: CatalogMatchesController::NEW_QUOTE, quantity: "25" }
    end
    line = QuoteLine.last
    assert_redirected_to quote_path(line.quote, line: line.id)
    assert_equal "RC-SS304-SHT-16GA-48X96-4", line.catalog_sku
    assert_equal "Acme Fabrication", line.quote.buyer_name

    post catalog_matches_path, params: { client_name: "Acme Fabrication", description: "304 SS sheet 16ga 4x8 x10" }
    follow_redirect!
    assert_select ".status--ready", "Match"
    assert_select ".match-card", 1
  end

  test "another browser cannot open a client's match request" do
    post catalog_matches_path, params: { client_name: "Acme Fabrication", description: "P1020 ingot" }
    request_record = MatchRequest.last

    other_browser = open_session
    other_browser.get catalog_match_path(request_record)
    assert_equal 404, other_browser.response.status

    other_browser.post approve_catalog_match_path(request_record), params: { part_numbers: [ "RC-AL-P1020-TBARINGOT" ] }
    assert_equal 404, other_browser.response.status
    assert_equal 0, QuoteLine.count
  end

  test "the rep can teach and forget a client's word" do
    post catalog_matches_path, params: { client_name: "Boro Marine", description: "S-330" }
    client = Client.find_by!(name: "Boro Marine")

    post teach_catalog_matches_path, params: { client_id: client.id, term: "KB", field: "finish", value: "#4" }
    assert_equal "#4", client.client_terms.find_by!(term: "kb").field_values["finish"]

    delete forget_catalog_matches_path, params: { client_id: client.id, term_id: client.client_terms.first.id }
    assert_empty client.client_terms.reload
  end

  test "a missing client or description is refused politely" do
    post catalog_matches_path, params: { client_name: "", description: "S-330" }
    assert_redirected_to catalog_matches_path(client_id: nil)
    assert_equal 0, MatchRequest.count
  end
end
