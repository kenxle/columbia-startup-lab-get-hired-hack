require "test_helper"
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

class TeachBuyerTermTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "teach-workspace")
    @line = @quote.quote_lines.first
  end

  def teach(**overrides)
    QuoteWorkspace::TeachBuyerTerm.call(**{
      quote: @quote, quote_line_id: @line.id, expected_revision: @quote.review_revision,
      term: " KB ", field: "finish", value: " #4 "
    }.merge(overrides))
  end

  test "explicit teaching stores trusted quote and line provenance without changing the quote" do
    @quote.approve!
    before_quote = @quote.attributes
    before_lines = @quote.quote_lines.map(&:attributes)
    record = teach
    assert_equal "kb", record.term
    assert_equal "taught", record.source
    assert_equal({ "finish" => "#4" }, record.field_values)
    assert_equal @quote.reference, record.meaning["confirmed_on"]
    assert_equal @quote.workspace_token, record.client.workspace_token
    provenance = record.meaning["provenance"]
    assert_equal "explicit_rep_teaching", provenance["method"]
    assert_equal @quote.id, provenance["quote_id"]
    assert_equal @quote.reference, provenance["quote_reference"]
    assert_equal @line.id, provenance["quote_line_id"]
    assert Time.iso8601(provenance["taught_at"])
    assert_equal before_quote, @quote.reload.attributes
    assert_equal before_lines, @quote.quote_lines.map(&:attributes)
  end

  test "second RFQ uses rep taught finish with source reference in its context" do
    teach
    second = Quote.create!(title: "Repeat order", buyer_name: @quote.buyer_name.downcase,
      source_text: "304 SS sheet 16ga 4x8 KB qty 10", workspace_token: @quote.workspace_token)
    context = QuoteWorkspace::BuyerContext.for(second)
    term = context[:buyer_terms].sole
    assert_equal @quote.reference, term["source_quote_reference"]
    assert_equal @quote.reference, term["confirmed_on"]
    assert_equal @line.id, term["provenance"]["quote_line_id"]
    reading = RfqProcessing::RulesParser.parse(second.source_text, buyer_terms: context[:buyer_terms])
    assert_equal "#4", reading.fields["finish"]
    assert_includes reading.evidence["finish"]["explanation"], "taught"
  end

  test "stale missing and structured revisions never write memory" do
    [ nil, "stale", [ @quote.review_revision ] ].each do |revision|
      assert_no_difference "ClientTerm.count" do
        assert_raises(Quote::StaleReview) { teach(expected_revision: revision) }
      end
    end
  end

  test "anonymous buyer unsupported fields and malformed inputs are rejected" do
    %w[price quantity part_number].each do |field|
      assert_raises(QuoteWorkspace::TeachBuyerTerm::Invalid) { teach(field: field) }
    end
    [ { term: " " }, { term: "x" * 121 }, { term: [ "kb" ] }, { field: [ "finish" ] },
      { value: " " }, { value: "x" * 201 }, { value: { value: "#4" } } ].each do |arguments|
      assert_raises(QuoteWorkspace::TeachBuyerTerm::Invalid) { teach(**arguments) }
    end
    @quote.update!(buyer_name: "")
    assert_raises(QuoteWorkspace::TeachBuyerTerm::Invalid) { teach }
    assert_equal 0, ClientTerm.count
  end

  test "numeric taught fields retain their types and source for a later RFQ" do
    teach(term: "16 ga", field: "thickness", value: "1/16")
    teach(term: "shop gauge", field: "gauge", value: "16")
    second = Quote.create!(title: "Repeat sheet order", buyer_name: @quote.buyer_name, source_text: "16 ga sheet",
      workspace_token: @quote.workspace_token)
    terms = QuoteWorkspace::BuyerContext.for(second)[:buyer_terms].index_by { |term| term["term"] }
    assert_equal 0.0625, terms.fetch("16 ga").dig("meaning", "fields", "thickness")
    assert_equal 16, terms.fetch("shop gauge").dig("meaning", "fields", "gauge")
    assert_equal @quote.reference, terms.fetch("16 ga")["confirmed_on"]
  end

  test "invalid or infinite numeric meanings do not reach buyer memory" do
    %w[gauge thickness].each do |field|
      %w[0 -1 NaN Infinity 1e999 1/0 nonsense].each do |value|
        assert_no_difference "ClientTerm.count" do
          assert_raises(QuoteWorkspace::TeachBuyerTerm::Invalid) { teach(field: field, value: value) }
        end
      end
    end
  end

  test "line must belong to the source quote" do
    other = QuoteWorkspace::Demo.create!(workspace_token: @quote.workspace_token)
    assert_raises(ActiveRecord::RecordNotFound) { teach(quote_line_id: other.quote_lines.first.id) }
    assert_equal 0, ClientTerm.count
  end

  test "repeat teaching updates one normalized term and does not reuse another workspace" do
    other = Client.create!(name: @quote.buyer_name, workspace_token: "other-workspace")
    other_record = other.client_terms.create!(term: "kb", source: "taught", meaning: { "fields" => { "finish" => "2B" } })
    record = teach
    assert_no_difference "ClientTerm.count" do
      assert_equal record.id, teach(term: "KB", value: "2B").id
    end
    assert_equal "2B", record.reload.field_values["finish"]
    assert_equal "2B", other_record.reload.field_values["finish"]
    refute_equal other_record.client_id, record.client_id
  end

  test "context rejects provenance from another workspace or another buyer" do
    record = teach
    other = QuoteWorkspace::Demo.create!(workspace_token: "other-workspace")
    provenance = record.meaning["provenance"].merge("quote_id" => other.id, "quote_reference" => other.reference)
    record.update!(meaning: record.meaning.merge("provenance" => provenance))
    term = QuoteWorkspace::BuyerContext.for(@quote)[:buyer_terms].sole
    refute term.key?("provenance")
    refute term.key?("source_quote_reference")
    assert_equal @quote.buyer_name, term["client_name"]
  end
end
