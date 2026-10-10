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
    assert_select ".match-card__specs", 2
    assert_select ".match-card__specs dd", text: "16 ga (0.0625 in)"
    assert_select "svg", 0

    assert_difference -> { QuoteLine.count }, 1 do
      post approve_catalog_match_path(request_record),
           params: { part_numbers: [ "RC-SS304-SHT-16GA-48X96-4" ], quote_id: CatalogMatchesController::NEW_QUOTE, quantity: "25" }
    end
    line = QuoteLine.last
    assert_redirected_to quote_path(line.quote, line: line.id)
    assert_equal "RC-SS304-SHT-16GA-48X96-4", line.catalog_sku
    assert_equal "Acme Fabrication", line.quote.buyer_name
    assert line.quote.sample_data?
    assert_nil line.unit_price

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

  test "double approval redirects to the original RFQ without duplicating or relearning" do
    request_record = exact_request
    approve(request_record)
    original_quote = Quote.find(request_record.reload.quote_id)
    before_counts = [ Quote.count, QuoteLine.count, ClientTerm.count ]
    before_terms = request_record.client.client_terms.map(&:attributes)
    before_request = request_record.attributes
    post approve_catalog_match_path(request_record), params: { part_numbers: [ "NOT-A-CANDIDATE" ], quote_id: "new", quantity: "999" }
    assert_redirected_to quote_path(original_quote)
    assert_equal before_counts, [ Quote.count, QuoteLine.count, ClientTerm.count ]
    assert_equal before_terms, request_record.client.client_terms.reload.map(&:attributes)
    assert_equal before_request, request_record.reload.attributes
  end

  test "unknown closest and no match items cannot create empty RFQs or learn terms" do
    [ "unknown", "closest", "no_match" ].each do |kind|
      request_record = exact_request
      result = request_record.result.deep_dup
      result["closest"] = result["candidates"]
      result["candidates"] = [] if kind == "closest"
      request_record.update!(result: result, outcome: kind == "no_match" ? "no_match" : "candidates")
      original_counts = [ Quote.count, QuoteLine.count, ClientTerm.count ]
      approve(request_record, pn: kind == "unknown" ? "UNKNOWN" : "RC-AL-P1020-TBARINGOT")
      assert_redirected_to catalog_match_path(request_record)
      assert_equal original_counts, [ Quote.count, QuoteLine.count, ClientTerm.count ]
      refute request_record.reload.approved?
    end
  end

  test "near and conflict checks stay unapproved without learning" do
    %w[near conflict].each do |status|
      request_record = exact_request
      result = request_record.result.deep_dup
      result["candidates"].first["checks"] = [ { "status" => status, "field" => "thickness" } ]
      request_record.update!(result: result)
      before_counts = [ Quote.count, QuoteLine.count, ClientTerm.count ]
      approve(request_record)
      assert_redirected_to catalog_match_path(request_record)
      assert_equal before_counts, [ Quote.count, QuoteLine.count, ClientTerm.count ]
      refute request_record.reload.approved?
    end
  end

  test "another buyer's same workspace RFQ cannot receive matched lines" do
    request_record = exact_request
    quote = Quote.create!(workspace_token: request_record.client.workspace_token, buyer_name: "Other buyer", title: "Other RFQ", source_text: "Request")
    before_quote = quote.attributes
    approve(request_record, quote_id: quote.id)
    assert_redirected_to catalog_match_path(request_record)
    assert_empty quote.quote_lines
    assert_equal before_quote, quote.reload.attributes
    refute request_record.reload.approved?
  end

  test "another workspace RFQ is inaccessible even for the same buyer" do
    request_record = exact_request
    quote = Quote.create!(workspace_token: "other-catalog-workspace", buyer_name: request_record.client.name, title: "Other RFQ", source_text: "Request")
    approve(request_record, quote_id: quote.id)
    assert_response :not_found
    assert_empty quote.quote_lines
    refute request_record.reload.approved?
  end

  test "same buyer normalized case is accepted and existing quote becomes sample labeled" do
    request_record = exact_request
    quote = Quote.create!(workspace_token: request_record.client.workspace_token, buyer_name: " acme   FABRICATION ", title: "Actual RFQ", source_text: "Request", sample_data: false)
    approve(request_record, quote_id: quote.id)
    assert_redirected_to quote_path(quote, line: quote.quote_lines.first.id)
    assert quote.reload.sample_data?
    assert_equal 1, quote.quote_lines.count
    assert_nil quote.quote_lines.first.unit_price
    follow_redirect!
    assert_select ".sample-banner", count: 1
  end

  test "invalid approval rolls back the new RFQ and all side effects" do
    request_record = exact_request
    before_counts = [ Quote.count, QuoteLine.count, ClientTerm.count ]
    approve(request_record, quantity: "-5")
    assert_redirected_to catalog_match_path(request_record)
    assert_equal before_counts, [ Quote.count, QuoteLine.count, ClientTerm.count ]
    refute request_record.reload.approved?
    assert_nil request_record.quote_id
  end

  private

  def exact_request
    post catalog_matches_path, params: { client_name: "Acme Fabrication", description: "P1020 ingot" }
    request_record = MatchRequest.last
    request_record.update!(outcome: "match", result: {
      "candidates" => [ { "pn" => "RC-AL-P1020-TBARINGOT", "checks" => [ { "field" => "grade", "status" => "exact" } ] } ],
      "closest" => []
    })
    request_record
  end

  def approve(request_record, pn: "RC-AL-P1020-TBARINGOT", quote_id: "new", quantity: "25")
    post approve_catalog_match_path(request_record), params: { part_numbers: [ pn ], quote_id: quote_id, quantity: quantity }
  end
end
