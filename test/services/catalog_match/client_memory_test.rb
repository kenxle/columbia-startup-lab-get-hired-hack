require "test_helper"

class CatalogMatch::ClientMemoryTest < ActiveSupport::TestCase
  setup do
    @acme = Client.create!(name: "Acme Fabrication", workspace_token: "t" * 43)
    @boro = Client.create!(name: "Boro Marine", workspace_token: "t" * 43)
    @quote = Quote.create!(title: "Acme RFQ", source_text: "see lines", workspace_token: "t" * 43)
  end

  def suggest(client, text) = CatalogMatch::Suggest.call(client: client, description: text)

  def approve(request, pn)
    CatalogMatch::Approve.call(match_request: request, part_numbers: [ pn ], quote: @quote)
  end

  test "an approved choice teaches the client's unknown word, for that client only" do
    first = suggest(@acme, "KB 16ga 4x8 x5")
    assert_equal "candidates", first.outcome
    approve(first, "RC-SS304-SHT-16GA-48X96-4")

    term = @acme.client_terms.find_by!(term: "kb")
    assert_equal "learned", term.source
    assert_equal "#4", term.field_values["finish"]
    assert_equal "stainless steel", term.field_values["material"]

    again = suggest(@acme, "KB 16ga 4x10 x3")
    assert_equal "match", again.outcome
    assert_equal "RC-SS304-SHT-16GA-48X120-4", again.suggested_part_numbers.first
    finish_check = again.result["candidates"].first["checks"].find { |check| check["field"] == "finish" }
    assert_equal "client_memory", finish_check["source"]

    other = suggest(@boro, "KB 16ga 4x10 x3")
    assert_equal "candidates", other.outcome, "Boro has not taught KB, so it must still ask"
  end

  test "the same word can mean different things for different clients" do
    CatalogMatch::ClientMemory.new(@acme).teach!(term: "HB", field: "finish", value: "#4")
    CatalogMatch::ClientMemory.new(@boro).teach!(term: "HB", field: "grade", value: "316/316L")

    acme = suggest(@acme, "HB 304 ss sheet 16 ga 48x96")
    boro = suggest(@boro, "HB ss sheet 16 ga 48x96")
    assert_equal "RC-SS304-SHT-16GA-48X96-4", acme.suggested_part_numbers.first
    assert_equal "RC-SS316-SHT-16GA-48X96-2B", boro.suggested_part_numbers.first
  end

  test "the buyer's explicit words beat a remembered meaning" do
    CatalogMatch::ClientMemory.new(@acme).teach!(term: "std", field: "finish", value: "#4")
    request = suggest(@acme, "std 304 ss sheet 16ga 4x8 2B")
    assert_equal "match", request.outcome
    assert_equal "RC-SS304-SHT-16GA-48X96-2B", request.suggested_part_numbers.first
  end

  test "an approved description is remembered as a phrase for that client" do
    manual = suggest(@acme, "304 SS sheet 16ga 4x8")
    assert_equal "candidates", manual.outcome
    approve(manual, "RC-SS304-SHT-16GA-48X96-2B")

    repeat = suggest(@acme, "304 SS sheet 16ga 4x8 x12")
    assert_equal "match", repeat.outcome
    assert_equal "RC-SS304-SHT-16GA-48X96-2B", repeat.suggested_part_numbers.first
    assert_equal 12, repeat.quantity
  end

  test "learning never overwrites a term the rep taught" do
    CatalogMatch::ClientMemory.new(@acme).teach!(term: "kb", field: "finish", value: "2B")
    request = suggest(@acme, "KB ss 304 sheet 16ga 4x8")
    approve(request, request.suggested_part_numbers.first)
    term = @acme.client_terms.find_by!(term: "kb")
    assert_equal "taught", term.source
    assert_equal({ "finish" => "2B" }, term.field_values)
  end
end

class CatalogMatch::ClientMemoryDemoTermsTest < ActiveSupport::TestCase
  setup do
    @acme = Client.create!(name: "Acme Fabrication", workspace_token: "t" * 43)
    @quote = Quote.create!(title: "Acme RFQ", source_text: "see lines", workspace_token: "t" * 43)
  end

  test "gauge, thickness and unit can be taught, with the RFQ that confirmed them" do
    term = CatalogMatch::ClientMemory.new(@acme).teach!(
      term: "16 ga", fields: { "gauge" => "16", "thickness" => "0.0625", "quantity_unit" => "sheet" }, confirmed_on: "RFQ-0001"
    )
    assert_equal({ "gauge" => 16, "thickness" => 0.0625, "quantity_unit" => "sheet" }, term.field_values)
    assert_equal "RFQ-0001", term.confirmed_on
    assert_match(/confirmed on RFQ-0001/, term.explanation_prefix)
  end

  test "a taught thickness resolves the gauge line next time, citing the RFQ" do
    CatalogMatch::ClientMemory.new(@acme).teach!(term: "16 ga", fields: { "thickness" => "0.0625" }, confirmed_on: "RFQ-0001")
    result = CatalogMatch::Matcher.call("stainless 304 sheet 16 ga 48 x 96 2B", client: @acme)
    assert_equal "match", result.outcome
    thickness = result.reading.fields["thickness"]
    assert_equal "client_memory", thickness["source"]
    assert_match(/RFQ-0001/, thickness["explanation"])
  end

  test "a bad number is refused" do
    assert_raises(ActiveRecord::RecordInvalid) do
      CatalogMatch::ClientMemory.new(@acme).teach!(term: "thin", field: "thickness", value: "about a sixteenth")
    end
  end

  test "ordinary words are never learned, and many unknown words teach none" do
    request = CatalogMatch::Suggest.call(client: @acme, description: "urgent ss 304 sheet 16ga 4x8")
    CatalogMatch::Approve.call(match_request: request, part_numbers: [ "RC-SS304-SHT-16GA-48X96-4" ], quote: @quote)
    assert_nil @acme.client_terms.find_by(term: "urgent")

    request = CatalogMatch::Suggest.call(client: @acme, description: "zz qq yy ss 304 sheet 16ga 4x10")
    CatalogMatch::Approve.call(match_request: request, part_numbers: [ "RC-SS304-SHT-16GA-48X120-4" ], quote: @quote)
    assert_empty @acme.client_terms.where(term: %w[zz qq yy])
  end
end

class CatalogMatch::ClientMemoryConfirmedWordingTest < ActiveSupport::TestCase
  test "a confirmed meaning of the buyer's exact words resolves the gauge trap next time" do
    client = Client.create!(name: "Northline Fabrication", workspace_token: "t" * 43)
    before = CatalogMatch::Matcher.call("Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets", client: client)
    assert_equal "candidates", before.outcome

    CatalogMatch::ClientMemory.new(client).teach!(term: "0.060 in", fields: { "gauge" => "16", "thickness" => "0.0625" },
                                                  confirmed_on: "RFQ-0001")
    after = CatalogMatch::Matcher.call("Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets", client: client)
    assert_equal "match", after.outcome
    assert_equal "RC-SS304-SHT-16GA-48X96-2B", after.best.item["pn"]
    assert_match(/confirmed on RFQ-0001/, after.reading.fields["thickness"]["explanation"])

    other_words = CatalogMatch::Matcher.call("Stainless 304, 0.125 in, 48 x 96, 2B", client: client)
    assert_equal 0.125, other_words.reading["thickness"], "a different thickness the buyer wrote is never replaced"
  end
end
