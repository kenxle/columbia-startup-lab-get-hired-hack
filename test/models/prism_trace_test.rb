require "test_helper"
require "minitest/mock"

class PrismTraceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  ENVIRONMENT = { "PRISMTRACE_API_KEY" => "test-placeholder", "PRISMTRACE_PROJECT_ID" => "project-test" }.freeze
  Response = Struct.new(:code, :body)

  def prepare_trace_hooks
    Rails.application.config.stub(:to_prepare, ->(&block) { block.call }) do
      load Rails.root.join("config/initializers/prism_trace.rb")
    end
  end

  # Exercise the app boundary before and after the independently shipped
  # provider patch. A temporary setter stands in for the new provider API.
  def with_processing_listener
    client = RfqProcessing::OpenAiCompatibleClient
    added_setter = !client.respond_to?(:trace_listener=)
    previous = client.trace_listener unless added_setter
    previous_catalog = CatalogMatch::LlmReader.trace_listener
    client.singleton_class.attr_accessor(:trace_listener) if added_setter
    prepare_trace_hooks
    yield client.trace_listener
  ensure
    CatalogMatch::LlmReader.trace_listener = previous_catalog
    client.trace_listener = previous
    client.singleton_class.remove_method(:trace_listener, :trace_listener=) if added_setter
  end

  test "processing hook maps outcomes and permits only safe metadata keys" do
    events = []
    run_id = SecureRandom.uuid
    with_processing_listener do |listener|
      QuoteWorkspace::PrismTrace.stub(:enqueue, ->(event) { events << event; true }) do
        %w[http_success http_error network_error model_mismatch malformed].each do |outcome|
          assert listener.call(model: "anthropic/claude-opus-5", elapsed_ms: 9, run_id: run_id,
            outcome: outcome, request_id: "PRIVATE", input: "PRIVATE RFQ", session_id: "PRIVATE BUYER")
        end
      end
      assert CatalogMatch::LlmReader.trace_listener.respond_to?(:call)
    end
    assert_equal %w[ok gateway_error gateway_error unparseable unparseable], events.map { |event| event[:outcome] }
    events.each do |event|
      assert_equal %i[elapsed_ms model outcome run_id], event.keys.sort
      assert_equal run_id, event[:run_id]
      refute_includes event.to_s, "PRIVATE"
    end
  end

  test "processing hook isolates exceptions at the app boundary" do
    with_processing_listener do |listener|
      QuoteWorkspace::PrismTrace.stub(:enqueue, ->(*) { raise "PRIVATE queue failure" }) do
        assert_equal false, listener.call(model: "claude-opus-5", outcome: "http_success", elapsed_ms: 1)
      end
    end
  end

  test "initializer tolerates an older processing client without a trace setter" do
    client = RfqProcessing::OpenAiCompatibleClient
    previous_catalog = CatalogMatch::LlmReader.trace_listener
    original = client.method(:respond_to?)
    client.stub(:respond_to?, ->(name, *arguments) { name == :trace_listener= ? false : original.call(name, *arguments) }) do
      prepare_trace_hooks
    end
    assert CatalogMatch::LlmReader.trace_listener.respond_to?(:call)
  ensure
    CatalogMatch::LlmReader.trace_listener = previous_catalog
  end

  test "success posts verified contract with only bounded metadata" do
    request = nil
    http = Object.new
    http.define_singleton_method(:request) do |value|
      request = value
      Response.new("200", '{"id":"trace-123"}')
    end
    result = QuoteWorkspace::PrismTrace.call({model: "anthropic/claude-opus-5", elapsed_ms: 42, outcome: "ok",
      input: "PRIVATE RFQ", output: "PRIVATE BUYER", request_id: "PRIVATE PROVIDER ID"}, env: ENVIRONMENT, http: http)
    assert_equal({status: "accepted", trace_id: "trace-123"}, result)
    assert_equal "/api/traces", request.path
    assert_equal "test-placeholder", request["X-PRISMtrace-Key"]
    body = JSON.parse(request.body)
    assert_equal "project-test", body["project_id"]
    assert_equal 42, body["latency_ms"]
    assert_includes body["input_messages"].first["content"], "Synthetic metadata"
    refute_includes request.body, "PRIVATE"
    refute_includes request.body, "test-placeholder"
  end

  test "missing credentials make no HTTP request" do
    http = Object.new
    http.define_singleton_method(:request) { |*| raise "must not send" }
    assert_equal({status: "disabled"}, QuoteWorkspace::PrismTrace.call({}, env: {}, http: http))
  end

  test "safe run UUID connects metadata and session while arbitrary identifiers are dropped" do
    run_id = "08C0FBA0-3BAD-4189-8AF0-9F6707A46400"
    requests = []
    http = Object.new
    http.define_singleton_method(:request) do |request|
      requests << JSON.parse(request.body)
      Response.new("200", '{"id":"trace-run"}')
    end
    QuoteWorkspace::PrismTrace.call({run_id: run_id}, env: ENVIRONMENT, http: http)
    assert_equal run_id.downcase, requests.last.dig("metadata", "run_id")
    assert_equal "metadata-#{run_id.downcase}", requests.last["session_id"]
    [nil, 123, "PRIVATE-RFQ-123", "buyer@example.invalid", "#{run_id}\n"].each do |invalid|
      event = {run_id: invalid, quote_id: 123, buyer: "PRIVATE BUYER"}
      refute QuoteWorkspace::PrismTrace.sanitize(event).key?("run_id")
      QuoteWorkspace::PrismTrace.call(event, env: ENVIRONMENT, http: http)
      replacement = requests.last.dig("metadata", "run_id")
      assert_match QuoteWorkspace::PrismTrace::RUN_UUID, replacement
      assert_equal "metadata-#{replacement}", requests.last["session_id"]
      refute_includes requests.last.to_json, "PRIVATE"
      refute_includes requests.last.to_json, "quote_id"
    end
    assert_equal requests.length, requests.map { |request| request["session_id"] }.uniq.length
  end

  test "errors timeouts and malformed success never propagate or claim acceptance" do
    [Response.new("401", "private error"), Response.new("200", "not json"), Response.new("200", "{}")].each do |response|
      http = Object.new
      http.define_singleton_method(:request) { |*| response }
      result = QuoteWorkspace::PrismTrace.call({}, env: ENVIRONMENT, http: http)
      refute_equal "accepted", result[:status]
      refute_includes result.to_s, "private"
    end
    http = Object.new
    http.define_singleton_method(:request) { |*| raise Net::ReadTimeout, "secret timeout text" }
    assert_equal({status: "failed"}, QuoteWorkspace::PrismTrace.call({}, env: ENVIRONMENT, http: http))
  end

  test "hook queues sanitized metadata instead of performing HTTP" do
    QuoteWorkspace::PrismTrace.stub(:configured?, true) do
      assert_enqueued_jobs 1, only: PrismTraceJob do
        assert QuoteWorkspace::PrismTrace.enqueue(model: "claude-opus-5", outcome: "ok", elapsed_ms: 5, input: "PRIVATE",
          run_id: "08c0fba0-3bad-4189-8af0-9f6707a46400")
      end
    end
    refute_includes enqueued_jobs.last[:args].to_s, "PRIVATE"
    assert_equal "08c0fba0-3bad-4189-8af0-9f6707a46400", enqueued_jobs.last[:args].first["run_id"]
  end
end
