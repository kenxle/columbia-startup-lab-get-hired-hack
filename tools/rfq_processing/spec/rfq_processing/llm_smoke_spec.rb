# frozen_string_literal: true

require "open3"
require "tempfile"
require "rbconfig"

RSpec.describe "llm-smoke CLI" do
  def smoke(mode, text: "Steel shot S-330, 2000 lb\n", stub: false, path: nil)
    Tempfile.create(["smoke-input", ".txt"]) do |input|
      input.write(text)
      input.flush
      Tempfile.create(["smoke-client", ".rb"]) do |preload|
        preload.write(<<~CODE)
          require #{File.expand_path('../../lib/rfq_processing', __dir__).dump}
          class RfqProcessing::LlmParser
            def self.from_env(**)
              count = 0
              at_exit { puts "offline HTTP calls: \#{count}" }
              http = lambda do |request|
                count += 1
                mode = ENV.fetch("SMOKE_TEST_MODE")
                if mode == "http_failure" || (mode == "partial" && count > 1)
                  [502, "PRIVATE_RESPONSE_SENTINEL"]
                else
                  model = mode == "wrong_model" ? "anthropic/claude-sonnet-4-6" : NICRRON_MODEL
                  shapes = { "array" => [], "scalar" => "wrong", "null" => nil, "empty_object" => {},
                             "bad_fields" => { "fields" => [], "evidence" => [], "unclear" => [] },
                             "bad_evidence" => { "fields" => {}, "evidence" => ["wrong"], "unclear" => [] } }
                  payload = shapes.fetch(mode) { { "fields" => {}, "evidence" => [], "unclear" => [] } }
                  content = mode == "bad_json" ? "not JSON" : JSON.generate(payload)
                  [200, JSON.generate("model" => model, "choices" => [{"message" => {"content" => content}}])]
                end
              end
              client = RfqProcessing::OpenAiCompatibleClient.new(api_key: "fake", base_url: "https://not-called.invalid", model: NICRRON_MODEL, http: http)
              def client.sleep(*) = nil
              new(client: client)
            end
          end
        CODE
        preload.flush
        args = [RbConfig.ruby]
        args += ["-r", preload.path] unless stub
        env = { "SMOKE_TEST_MODE" => mode, "RFQ_LLM_SMOKE_STUB" => stub ? "1" : nil }
        Open3.capture3(env, *args, File.expand_path("../../bin/llm-smoke", __dir__), (path || input.path))
      end
    end
  end

  %w[http_failure wrong_model bad_json array scalar null empty_object bad_fields bad_evidence].each do |mode|
    it "fails for #{mode} even when deterministic parsing succeeds" do
      out, err, status = smoke(mode)
      expect(status.exitstatus).to eq(1)
      expect(out).to include("accepted responses 0; failed/rejected responses 1", "FAILED:")
      expect(out).not_to include("PASSED:")
      expect(err).not_to include("PRIVATE_RESPONSE_SENTINEL")
    end
  end

  it "accepts a valid model response that adds no fields" do
    out, _, status = smoke("success")
    expect(status.exitstatus).to eq(0)
    expect(out).to include("claude added: (nothing)", "accepted responses 1; failed/rejected responses 0", "PASSED:")
  end

  it "fails partial provider success" do
    out, _, status = smoke("partial", text: "Steel shot S-330, 2000 lb\nSteel grit G-40, 1000 lb\n")
    expect(status.exitstatus).to eq(1)
    expect(out).to include("accepted responses 1; failed/rejected responses 1", "FAILED:")
  end

  it "fails when no item line exercised the provider" do
    out, _, status = smoke("success", text: "Hello\nThanks\n")
    expect(status.exitstatus).to eq(1)
    expect(out).to include("accepted responses 0", "FAILED:")
  end

  it "labels successful stubs without claiming a live provider test" do
    out, _, status = smoke("success", stub: true)
    expect(status.exitstatus).to eq(0)
    expect(out).to include("STUB, no live provider tested", "from the stub only")
  end

  it "tests only the assembled Transnet item, not tender boilerplate or wrapped cells" do
    path = File.expand_path("../../../../docs/example_rfqs/transnet-steel-shot-2024/source.pdf", __dir__)
    out, _, status = smoke("success", path: path)
    expect(status.exitstatus).to eq(0)
    expect(out).to include("lines: 1  lines where Claude added fields:", "accepted responses 1; failed/rejected responses 0")
    expect(out).to include("offline HTTP calls: 1", "quantity=50000", "quantity_unit=kg")
  end

end
