require "test_helper"
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s
require "minitest/mock"

class LiveModelsTest < ActiveSupport::TestCase
  test "only explicit development opt in permits the parser" do
    previous = ENV["RFQ_LIVE_MODELS"]
    %w[development test production].each do |environment|
      Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new(environment)) do
        [nil, "", "true", "0", "1"].each do |setting|
          ENV["RFQ_LIVE_MODELS"] = setting
          expected = environment == "development" && setting == "1"
          assert_equal expected, QuoteWorkspace::LiveModels.enabled?
          if expected
            assert_nil QuoteWorkspace::LiveModels.parser_argument
          else
            assert_equal false, QuoteWorkspace::LiveModels.parser_argument
          end
        end
      end
    end
  ensure
    ENV["RFQ_LIVE_MODELS"] = previous
  end

  test "opted in intake falls back to rules without a configured parser and never initializes catalog model" do
    quote = Quote.create!(title: "Optional model", source_text: "S-330 steel shot, 100 lb", workspace_token: "live-model-test")
    calls = 0
    QuoteWorkspace::LiveModels.stub(:enabled?, true) do
      RfqProcessing::LlmParser.stub(:from_env, -> { calls += 1; nil }) do
        CatalogMatch::LlmReader.stub(:default, -> { flunk "Catalog provider remains disabled" }) do
          run = QuoteWorkspace::ProcessRfq.enqueue(quote: quote, expected_revision: quote.review_revision)
          assert_equal "succeeded", QuoteWorkspace::ProcessRfq.perform(run.id).status
        end
      end
    end
    assert_equal 1, calls
    assert_equal "RC-STEELSHOT-S330", quote.reload.quote_lines.first.catalog_sku
    assert_equal BigDecimal("0.4"), quote.quote_lines.first.unit_price
  end

  test "opted in provider failure retains rules and holds without model prices" do
    quote = Quote.create!(title: "Model unavailable", source_text: "304 SS sheet 16ga 4x8, 20 sheets", workspace_token: "live-fallback-test")
    reads = 0
    client = Object.new
    client.define_singleton_method(:chat) { |**| reads += 1; raise IOError, "provider unavailable" }
    parser = RfqProcessing::LlmParser.new(client: client)
    QuoteWorkspace::LiveModels.stub(:enabled?, true) do
      RfqProcessing::LlmParser.stub(:from_env, parser) do
        run = QuoteWorkspace::ProcessRfq.enqueue(quote: quote, expected_revision: quote.review_revision)
        assert_equal "succeeded", QuoteWorkspace::ProcessRfq.perform(run.id).status
      end
    end
    assert_equal 1, reads
    line = quote.reload.quote_lines.first
    assert_equal "304", line.spec["grade"]
    assert_nil line.unit_price
    refute line.quotable?
  end

  test "accepted model fills keep source evidence while rule conflicts and price holds survive" do
    quote = Quote.create!(title: "Model evidence", source_text: "Stnless sht 16ga 4x8 qty 5", workspace_token: "live-evidence-test")
    payload = {
      "fields" => { "material" => "stainless steel", "quantity" => 50, "unit_price" => 1 },
      "evidence" => [
        { "field" => "material", "text" => "Stnless", "note" => "misspelling of stainless", "confidence" => 0.95 },
        { "field" => "quantity", "text" => "qty 5", "note" => "conflicting model quantity", "confidence" => 0.99 }
      ], "unclear" => []
    }
    client = Object.new
    client.define_singleton_method(:chat) { |**| { "model" => "claude-opus-5", "text" => payload.to_json } }
    parser = RfqProcessing::LlmParser.new(client: client)
    QuoteWorkspace::LiveModels.stub(:enabled?, true) do
      RfqProcessing::LlmParser.stub(:from_env, parser) do
        run = QuoteWorkspace::ProcessRfq.enqueue(quote: quote, expected_revision: quote.review_revision)
        assert_equal "succeeded", QuoteWorkspace::ProcessRfq.perform(run.id).status
      end
    end
    line = quote.reload.quote_lines.first
    assert_equal "stainless steel", line.spec["material"]
    assert_equal "Stnless", line.evidence.dig("material", "text")
    assert_includes line.evidence.dig("material", "explanation"), "read by Claude"
    assert_equal BigDecimal("5"), line.quantity
    assert_includes line.processing.fetch("conflicts").map { |conflict| conflict["code"] }, "llm_disagrees"
    assert_nil line.unit_price
    refute line.quotable?
  end
end
