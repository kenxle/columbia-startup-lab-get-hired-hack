require "test_helper"
require "minitest/mock"

class BuyerContextTest < ActiveSupport::TestCase
  setup do
    @quote = Quote.create!(title: "Buyer context RFQ", buyer_name: " Northline   Fabrication ",
      workspace_token: "buyer-context-a", source_text: "20 sheets")
  end

  def context(quote = @quote)
    QuoteWorkspace::BuyerContext.for(quote)
  end

  test "named buyers create one normalized workspace client and reuse it" do
    first = nil
    assert_difference "Client.count", 1 do
      first = context
    end
    assert_equal "Northline Fabrication", first[:client].name
    assert_equal @quote.workspace_token, first[:client].workspace_token
    assert_empty first[:buyer_terms]
    assert_no_difference "Client.count" do
      assert_equal first[:client].id, context[:client].id
    end
  end

  test "blank buyer names never create or reuse an anonymous client" do
    [ nil, "", " \n\t " ].each do |name|
      @quote.buyer_name = name
      assert_no_difference "Client.count" do
        result = context
        assert_nil result[:client]
        assert_empty result[:buyer_terms]
      end
    end
  end

  test "same buyer in another workspace cannot leak client or learned terms" do
    other = Client.create!(name: "Northline Fabrication", workspace_token: "buyer-context-b")
    other.client_terms.create!(term: "secret", meaning: { "fields" => { "grade" => "SECRET-GRADE" } }, source: "taught")
    result = context
    refute_equal other.id, result[:client].id
    assert_equal @quote.workspace_token, result[:client].workspace_token
    assert_empty result[:buyer_terms]
  end

  test "name matching ignores case and normalized spacing including Unicode" do
    existing = Client.create!(name: "Nörthline Fabrication", workspace_token: @quote.workspace_token)
    @quote.buyer_name = " NÖRTHLINE   fabrication "
    assert_no_difference "Client.count" do
      assert_equal existing.id, context[:client].id
    end
  end

  test "only rep taught terms carry record fields and client provenance into processing" do
    client = context[:client]
    taught = client.client_terms.create!(term: "KB", meaning: { "fields" => { "finish" => "#4" }, "client_name" => "SPOOFED", "trusted" => true }, source: "taught", times_confirmed: 1)
    learned = client.client_terms.create!(term: "our bolt", meaning: { "part_number" => "AN3-4A", "private" => "HIDDEN" }, source: "learned", times_confirmed: 2)
    result = context
    assert_equal [
      { "term" => "kb", "meaning" => { "fields" => { "finish" => "#4" } }, "source" => "taught", "times_confirmed" => 1, "client_name" => client.name }
    ], result[:buyer_terms]
    result[:buyer_terms].first["meaning"]["fields"]["finish"] = "tampered snapshot"
    assert_equal "#4", taught.reload.field_values["finish"]
    assert_equal "AN3-4A", learned.reload.part_number
  end

  test "a second RFQ reuses existing buyer memory without changing it or the quote" do
    client = context[:client]
    term = client.client_terms.create!(term: "KB", meaning: { "fields" => { "finish" => "#4" } }, source: "taught")
    second = Quote.create!(title: "Second request", buyer_name: "northline fabrication", source_text: "KB sheet", workspace_token: @quote.workspace_token)
    before_quote = second.attributes
    before_term = term.attributes
    assert_no_difference "ClientTerm.count" do
      result = context(second)
      assert_equal client.id, result[:client].id
      assert_equal "#4", result[:buyer_terms].first["meaning"]["fields"]["finish"]
    end
    assert_equal before_quote, second.reload.attributes
    assert_equal before_term, term.reload.attributes
  end

  test "creation uniqueness race rereads only a matching scoped client" do
    context_service = QuoteWorkspace::BuyerContext.new(@quote)
    existing = Client.create!(name: "Northline Fabrication", workspace_token: @quote.workspace_token)
    calls = 0
    lookup = lambda do
      calls += 1
      calls == 1 ? nil : existing
    end
    context_service.stub(:find_client, lookup) do
      assert_equal existing.id, context_service.call[:client].id
    end
  end

  test "unrelated validation failures propagate instead of becoming anonymous contexts" do
    @quote.workspace_token = nil
    assert_raises(ActiveRecord::RecordInvalid) { context }
  end
end
