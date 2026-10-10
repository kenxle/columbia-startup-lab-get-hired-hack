require "test_helper"

class CatalogMatch::LlmReaderTest < ActiveSupport::TestCase
  def reader(answer)
    transport = lambda do |request|
      @last_request = request
      { "model" => "anthropic/claude-opus-5",
        "choices" => [ { "message" => { "role" => "assistant", "content" => answer.to_json } } ] }.to_json
    end
    CatalogMatch::LlmReader.new(api_key: "test", transport: transport)
  end

  test "fields are accepted only with evidence that is really in the line" do
    line = "need twenty sheets of the thin stainless, 16 gauge, four by eight, brushed"
    given = reader(
      "fields" => { "material" => "stainless steel", "form" => "sheet", "finish" => "#4", "gauge" => 16, "quantity" => 20,
                    "width" => 48, "length" => 96, "grade" => "304" },
      "evidence" => { "material" => "stainless", "form" => "sheets", "finish" => "brushed", "gauge" => "16 gauge",
                      "quantity" => "twenty", "width" => "four by eight", "length" => "four by eight", "grade" => "304" }
    ).read(line)
    assert_equal "stainless steel", given["material"]["value"]
    assert_equal "#4", given["finish"]["value"]
    assert_equal "llm", given["finish"]["source"]
    assert_equal "brushed", given["finish"]["text"]
    assert_nil given["grade"], "304 is not in the line, so it must not be accepted"
    assert_equal "anthropic/claude-opus-5", @last_request["model"]
  end

  test "the matcher uses the LLM only for what the rules left open, and the rules win" do
    llm = reader(
      "fields" => { "material" => "stainless steel", "form" => "sheet", "finish" => "#4", "gauge" => 14, "width" => 48, "length" => 96, "quantity" => 20 },
      "evidence" => { "material" => "stainless", "form" => "sheets", "finish" => "brushed", "gauge" => "16 gauge",
                      "width" => "four by eight", "length" => "four by eight", "quantity" => "twenty" }
    )
    result = CatalogMatch::Matcher.call("twenty sheets of the thin stainless, 16 gauge, four by eight, brushed", llm: llm)
    assert_equal "match", result.outcome, "finish from the LLM narrows it to the #4 sheet"
    assert_equal 16, result.reading["gauge"], "the rules read 16 gauge; the LLM's 14 must not replace it"
    assert_equal "#4", result.reading["finish"]
    assert_equal 20, result.reading["quantity"], "the rules cannot read 'twenty'; the LLM can"
    assert_equal "llm", result.reading.fields["quantity"]["source"]
    assert_includes result.candidates.map { |candidate| candidate.item["pn"] }, "RC-SS304-SHT-16GA-48X96-4"
  end

  test "a clear line never calls the LLM" do
    called = false
    llm = CatalogMatch::LlmReader.new(api_key: "test", transport: ->(_) { called = true; "{}" })
    CatalogMatch::Matcher.call("16 ga galv sheet 4x10 x 25", llm: llm)
    assert_not called
  end

  test "a gateway failure leaves the rules reading in place" do
    llm = CatalogMatch::LlmReader.new(api_key: "test", transport: ->(_) { raise IOError, "gateway down" })
    result = CatalogMatch::Matcher.call("the usual stainless, brushed, 16 gauge four by eight", llm: llm)
    assert_equal 16, result.reading["gauge"]
  end

  test "the LLM is off in tests unless asked for" do
    assert_nil CatalogMatch::LlmReader.default
  end

  test "missing and substituted model identities cannot contribute fields" do
    [nil, "", "anthropic/claude-opus-5.5", "claude-opus-5.5", "claude-opus-5-unverified", "claude-sonnet-5"].each do |model|
      transport = ->(_) {
        { "model" => model, "choices" => [{ "message" => { "content" => {
          "fields" => { "finish" => "#4" }, "evidence" => { "finish" => "brushed" }
        }.to_json } }] }.to_json
      }
      assert_nil CatalogMatch::LlmReader.new(model: "anthropic/claude-opus-5", transport: transport).read("brushed"), model.inspect
    end
  end

  test "exact model identities and dated versions are accepted" do
    ["anthropic/claude-opus-5", "claude-opus-5", "Anthropic/Claude-Opus-5", "claude-opus-5-20261010"].each do |model|
      transport = ->(_) {
        { "model" => model, "choices" => [{ "message" => { "content" => {
          "fields" => { "finish" => "#4" }, "evidence" => { "finish" => "brushed" }
        }.to_json } }] }.to_json
      }
      assert_equal "#4", CatalogMatch::LlmReader.new(model: "anthropic/claude-opus-5", transport: transport).read("brushed").dig("finish", "value")
    end
  end
end

class CatalogMatch::LlmReaderTraceTest < ActiveSupport::TestCase
  teardown { CatalogMatch::LlmReader.trace_listener = nil }

  test "a trace listener hears every gateway call without affecting the reading" do
    heard = []
    CatalogMatch::LlmReader.trace_listener = ->(event) { heard << event }
    transport = ->(_) { { "id" => "gen-1", "model" => "anthropic/claude-opus-5", "choices" => [ { "message" => { "content" => '{"fields":{},"evidence":{}}' } } ] }.to_json }
    assert_equal({}, CatalogMatch::LlmReader.new(api_key: "t", transport: transport).read("something"))
    assert_equal [ "ok" ], heard.map { |event| event[:outcome] }
    assert_equal "gen-1", heard.first[:request_id]

    CatalogMatch::LlmReader.trace_listener = ->(_) { raise "tracing broke" }
    assert_equal({}, CatalogMatch::LlmReader.new(api_key: "t", transport: transport).read("something"))
  end
end
