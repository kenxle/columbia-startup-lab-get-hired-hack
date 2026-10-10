# frozen_string_literal: true

RSpec.describe RfqProcessing::JevClient do
  let(:questions) { { "flag_0" => { "type" => "noul", "instructions" => "Does this request apply?" } } }
  let(:payload) { { "model" => "jev-1.13.0", "answers" => { "flag_0" => { "type" => "noul", "noul" => 0.73 } } } }

  def evaluate(body, status: 200, model: "jev-latest")
    client = described_class.new(api_key: "PRIVATE_TEST_KEY", model: model, http: ->(_request) { [status, body] })
    client.evaluate(state: "3.1", questions: questions)
  end

  it "uses the official endpoint and request shape and accepts a versioned alias response" do
    seen = nil
    client = described_class.new(api_key: "PRIVATE_TEST_KEY", http: ->(request) { seen = request; [200, JSON.generate(payload)] })
    expect(client.evaluate(state: { "item_text" => "3.1" }, questions: questions)).to eq("model" => "jev-1.13.0", "probabilities" => { "flag_0" => 0.73 })
    expect(seen.uri.to_s).to eq("https://api.typesafe.ai/v1/systemone")
    expect(seen["Authorization"]).to eq("Bearer PRIVATE_TEST_KEY")
    expect(JSON.parse(seen.body)).to eq("model" => "jev-latest", "state" => { "item_text" => "3.1" }, "questions" => questions)
  end

  it "is disabled without a key" do
    expect(described_class.from_env(env: {})).to be_nil
    transport = double("transport")
    expect(transport).not_to receive(:call)
    expect(described_class.new(api_key: "", http: transport).evaluate(state: "x", questions: questions)).to be_nil
  end

  it "rejects non-200, malformed, oversized and incomplete responses without logging secrets" do
    expect do
      expect(evaluate("PRIVATE_SERVER_BODY PRIVATE_TEST_KEY", status: 502)).to be_nil
      ["not json", "[]", "{}", "x" * 65_537, JSON.generate(payload.merge("answers" => {}))].each do |body|
        expect(evaluate(body)).to be_nil
      end
    end.to output("").to_stderr
  end

  it "rejects out-of-range, NaN, string, boolean and wrong-type probabilities" do
    [-0.1, 1.1, "0.7", nil, true].each do |value|
      bad = Marshal.load(Marshal.dump(payload))
      bad["answers"]["flag_0"]["noul"] = value
      expect(evaluate(JSON.generate(bad))).to be_nil
    end
    expect(evaluate('{"model":"jev-1.13.0","answers":{"flag_0":{"type":"noul","noul":NaN}}}')).to be_nil
    bad = Marshal.load(Marshal.dump(payload))
    bad["answers"]["flag_0"]["type"] = "choice"
    expect(evaluate(JSON.generate(bad))).to be_nil
  end

  it "rejects missing and wrong model identities while accepting the requested exact version" do
    expect(evaluate(JSON.generate(payload.merge("model" => "other-model")))).to be_nil
    expect(evaluate(JSON.generate(payload.except("model")))).to be_nil
    expect(evaluate(JSON.generate(payload), model: "jev-1.12.0")).to be_nil
    expect(evaluate(JSON.generate(payload), model: "jev-1.13.0")).not_to be_nil
  end

  it "does not retry a timeout or print its private details" do
    calls = 0
    client = described_class.new(api_key: "PRIVATE_TEST_KEY", http: ->(_) { calls += 1; raise Net::ReadTimeout, "PRIVATE_TEST_KEY" })
    expect { expect(client.evaluate(state: "x", questions: questions)).to be_nil }.to output("").to_stderr
    expect(calls).to eq(1)
  end

  it "sets bounded socket timeouts and disables Net::HTTP retries" do
    http = double("http")
    expect(Net::HTTP).to receive(:new).with("api.typesafe.ai", 443).and_return(http)
    expect(http).to receive(:use_ssl=).with(true)
    expect(http).to receive(:open_timeout=).with(2)
    expect(http).to receive(:read_timeout=).with(3)
    expect(http).to receive(:write_timeout=).with(3)
    expect(http).to receive(:max_retries=).with(0)
    expect(http).to receive(:start).and_raise(Net::OpenTimeout)
    expect(described_class.new(api_key: "fake").evaluate(state: "x", questions: questions)).to be_nil
  end

  it "refuses an excessive question batch" do
    transport = double("transport")
    expect(transport).not_to receive(:call)
    client = described_class.new(api_key: "fake", http: transport)
    expect(client.evaluate(state: "x", questions: (1..5).to_h { |i| [i.to_s, {}] })).to be_nil
  end
end
