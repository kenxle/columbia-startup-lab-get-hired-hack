# frozen_string_literal: true

require "net/http"
require "stringio"

RSpec.describe RfqProcessing::OpenAiCompatibleClient do
  let(:schema) { RfqProcessing::LlmParser::SCHEMA }
  let(:model) { "anthropic/claude-opus-5" }
  let(:reading_json) { JSON.generate("fields" => { "material" => "stainless steel" }, "evidence" => [], "unclear" => []) }

  # A chat completion body the way a gateway writes it.
  def completion(content, model: "anthropic/claude-opus-5", with_model: true)
    body = { "id" => "chatcmpl-1", "object" => "chat.completion",
             "choices" => [{ "index" => 0, "finish_reason" => "stop", "message" => { "role" => "assistant", "content" => content } }] }
    body["model"] = model if with_model
    JSON.generate(body)
  end

  # An http callable that answers from a queue and records every request. An Exception in the queue is raised.
  def fake_http(*answers)
    requests = []
    callable = lambda do |request|
      requests << request
      answer = answers.shift
      raise "fake_http ran out of answers" if answer.nil?
      raise answer if answer.is_a?(Exception)

      answer
    end
    [callable, requests]
  end

  def client_for(http, base_url: "https://gateway.example/v1")
    described_class.new(api_key: "test-key-not-real", base_url: base_url, model: model, http: http)
  end

  def chat(client, user: "304 SS sheet 16ga 4x8")
    client.chat(system: RfqProcessing::LlmParser::SYSTEM_PROMPT, user: user, schema: schema, max_tokens: 2048)
  end

  # [the block's value, everything it wrote to stderr]
  def capturing_stderr
    original = $stderr
    $stderr = StringIO.new
    result = yield
    [result, $stderr.string]
  ensure
    $stderr = original
  end

  it "never logs response or exception content for chat and model diagnostics" do
    sentinel = "PRIVATE_RFQ_CONTENT_SENTINEL"
    [[500, sentinel], [200, sentinel], [200, JSON.generate("error" => sentinel)], RuntimeError.new(sentinel)].each do |response|
      http, = fake_http(response)
      result, error = capturing_stderr { chat(client_for(http), user: sentinel) }
      expect(result).to be_nil
      expect(error).not_to include(sentinel)
      expect(error).not_to be_empty

      http, = fake_http(response)
      result, error = capturing_stderr { client_for(http).models }
      expect(result).to be_nil
      expect(error).not_to include(sentinel)
      expect(error).not_to be_empty
    end
  end

  describe "#chat" do
    it "posts one chat completion with the bearer key, JSON content type, and a strict json_schema response_format" do
      http, requests = fake_http([200, completion(reading_json)])
      result = chat(client_for(http, base_url: "https://gateway.example/v1/"))

      expect(result).to eq("text" => reading_json, "model" => "anthropic/claude-opus-5")
      expect(requests.size).to eq(1)
      request = requests.first
      expect(request["method"]).to eq("POST")
      expect(request["url"]).to eq("https://gateway.example/v1/chat/completions")
      expect(request["headers"]).to eq("Authorization" => "Bearer test-key-not-real", "Content-Type" => "application/json")
      body = request["body"]
      expect(body).to be_a(Hash)
      expect(body["model"]).to eq("anthropic/claude-opus-5")
      expect(body["messages"]).to eq([{ "role" => "system", "content" => RfqProcessing::LlmParser::SYSTEM_PROMPT },
                                      { "role" => "user", "content" => "304 SS sheet 16ga 4x8" }])
      expect(body["max_tokens"]).to eq(2048)
      expect(body["temperature"]).to eq(0)
      expect(body["response_format"]).to eq("type" => "json_schema",
                                            "json_schema" => { "name" => "rfq_line", "strict" => true, "schema" => schema })
      expect(JSON.generate(body)).not_to include("test-key-not-real")
    end

    it "retries once without response_format when the gateway rejects response_format, with the schema written into the system message" do
      http, requests = fake_http([400, '{"error":{"message":"response_format is not supported"}}'], [200, completion(reading_json)])
      result, err = capturing_stderr { chat(client_for(http)) }

      expect(result).to eq("text" => reading_json, "model" => "anthropic/claude-opus-5")
      expect(requests.size).to eq(2)
      expect(requests.first["body"]).to include("response_format")
      retry_body = requests.last["body"]
      expect(retry_body).not_to include("response_format")
      expect(retry_body["model"]).to eq("anthropic/claude-opus-5")
      expect(retry_body["max_tokens"]).to eq(2048)
      expect(retry_body["temperature"]).to eq(0)
      system_text = retry_body["messages"].first["content"]
      expect(retry_body["messages"].first["role"]).to eq("system")
      expect(system_text).to start_with(RfqProcessing::LlmParser::SYSTEM_PROMPT.rstrip)
      expect(system_text).to include("Answer with exactly one JSON object and nothing else")
      expect(system_text).to include(JSON.generate(schema))
      expect(retry_body["messages"].last).to eq("role" => "user", "content" => "304 SS sheet 16ga 4x8")
      expect(err).to include("400")
      expect(err.lines.size).to eq(1)
    end

    it "never retries a second time: 400 then 400 is nil after exactly two requests" do
      http, requests = fake_http([400, "response_format not supported"], [400, "still no"])
      result, err = capturing_stderr { chat(client_for(http)) }

      expect(result).to be_nil
      expect(requests.size).to eq(2)
      expect(err).to include("400")
      expect(err.lines.size).to eq(1)
    end

    it "is nil when the retry without response_format answers 500" do
      http, requests = fake_http([400, "response_format not supported"], [500, "boom"])
      result, err = capturing_stderr { chat(client_for(http)) }

      expect(result).to be_nil
      expect(requests.size).to eq(2)
      expect(err).to match(/400 with response_format, then 500/)
      expect(err.lines.size).to eq(1)
    end

    it "is nil on a 500 with no retry, naming the status in one warn line" do
      http, requests = fake_http([500, "internal"])
      result, err = capturing_stderr { chat(client_for(http)) }

      expect(result).to be_nil
      expect(requests.size).to eq(1)
      expect(err).to include("500")
      expect(err.lines.size).to eq(1)
    end

    it "does not retry authentication, quota, or unrelated validation failures as schema failures" do
      [400, 401, 403, 404, 429].each do |status|
        http, requests = fake_http([status, '{"error":{"message":"request denied"}}'])
        result, err = capturing_stderr { chat(client_for(http)) }
        expect(result).to be_nil
        expect(requests.size).to eq(1)
        expect(err).to include(status.to_s)
      end
    end

    it "redacts an echoed API key from gateway error bodies and transport exceptions" do
      [[500, "invalid key test-key-not-real"], RuntimeError.new("test-key-not-real")].each do |response|
        http, = fake_http(response)
        result, err = capturing_stderr { chat(client_for(http)) }
        expect(result).to be_nil
        expect(err).not_to include("test-key-not-real")
      end
    end

    [502, 503, 504].each do |status|
      it "retries the same request once after a one second pause on #{status}" do
        http, requests = fake_http([status, "bad gateway"], [200, completion(reading_json)])
        client = client_for(http)
        allow(client).to receive(:sleep)
        result, err = capturing_stderr { chat(client) }

        expect(result).to eq("text" => reading_json, "model" => "anthropic/claude-opus-5")
        expect(requests.size).to eq(2)
        expect(requests.last).to eq(requests.first) # the same request, response_format and all
        expect(requests.last["body"]).to include("response_format")
        expect(client).to have_received(:sleep).with(1).once
        expect(err).to eq("")
      end
    end

    it "gives up after one transient retry with a single warn line naming the status and the path, never the key" do
      http, requests = fake_http([502, "bad gateway"], [503, "unavailable"])
      client = client_for(http)
      allow(client).to receive(:sleep)
      result, err = capturing_stderr { chat(client) }

      expect(result).to be_nil
      expect(requests.size).to eq(2)
      expect(client).to have_received(:sleep).with(1).once
      expect(err.lines.size).to eq(1)
      expect(err).to include("503", "chat endpoint")
      expect(err).not_to include("test-key-not-real")
      expect(client.last_status).to eq(503)
    end

    it "also retries a transient status once on the request that has no response_format" do
      http, requests = fake_http([400, "response_format not supported"], [504, "timeout"], [200, completion(reading_json)])
      client = client_for(http)
      allow(client).to receive(:sleep)
      result, = capturing_stderr { chat(client) }

      expect(result).to eq("text" => reading_json, "model" => "anthropic/claude-opus-5")
      expect(requests.size).to eq(3)
      expect(requests[2]).to eq(requests[1])
      expect(requests[1]["body"]).not_to include("response_format")
      expect(client).to have_received(:sleep).with(1).once
    end

    it "is nil, with one warn line and no exception, when the callable raises a timeout or a socket error" do
      [Net::OpenTimeout.new("execution expired"), Net::ReadTimeout.new, SocketError.new("getaddrinfo: nodename nor servname provided"),
       Errno::ECONNREFUSED.new, OpenSSL::SSL::SSLError.new("certificate verify failed")].each do |error|
        http, requests = fake_http(error)
        result = nil
        err = nil
        expect { result, err = capturing_stderr { chat(client_for(http)) } }.not_to raise_error
        expect(result).to be_nil
        expect(requests.size).to eq(1)
        expect(err).to include(error.class.name)
        expect(err).not_to include("test-key-not-real")
        expect(err.lines.size).to eq(1)
      end
    end

    it "is nil when the body has no choices[0].message.content" do
      ['{"model":"anthropic/claude-opus-5"}', '{"choices":[]}', '{"choices":[{"message":{"role":"assistant"}}]}',
       '{"choices":[{"message":{"content":"   "}}]}', '{"choices":"nope"}', "[]"].each do |body|
        http, = fake_http([200, body])
        result, err = capturing_stderr { chat(client_for(http)) }

        expect(result).to be_nil
        expect(err).to include("choices[0].message.content")
        expect(err.lines.size).to eq(1)
      end
    end

    it "is nil when a 2xx body is not JSON" do
      http, = fake_http([200, "<html>bad gateway page</html>"])
      result, err = capturing_stderr { chat(client_for(http)) }

      expect(result).to be_nil
      expect(err).to include("not JSON")
      expect(err.lines.size).to eq(1)
    end

    it "passes the gateway's model name through, and nil when the body has none" do
      http, = fake_http([200, completion(reading_json, model: "anthropic/claude-opus-5-20260901")])
      expect(chat(client_for(http))).to eq("text" => reading_json, "model" => "anthropic/claude-opus-5-20260901")

      http, = fake_http([200, completion(reading_json, with_model: false)])
      expect(chat(client_for(http))).to eq("text" => reading_json, "model" => nil)
    end

    it "joins text parts when the content comes back as an array of parts" do
      content = [{ "type" => "text", "text" => "{\"fields\":" }, { "type" => "text", "text" => "{}}" }]
      http, = fake_http([200, completion(content)])
      expect(chat(client_for(http))["text"]).to eq('{"fields":{}}')
    end
  end

  describe "#models" do
    it "GETs <base_url>/models with the bearer key and returns the ids, in the OpenAI shape or a bare array" do
      listing = JSON.generate("object" => "list", "data" => [{ "id" => "anthropic/claude-opus-5", "object" => "model" },
                                                              { "id" => "anthropic/claude-sonnet-4-6" }, { "object" => "model" }])
      http, requests = fake_http([200, listing])
      client = client_for(http, base_url: "https://gateway.example/v1/")

      expect(client.models).to eq(["anthropic/claude-opus-5", "anthropic/claude-sonnet-4-6"])
      expect(client.last_status).to eq(200)
      expect(requests.size).to eq(1)
      expect(requests.first).to eq("method" => "GET", "url" => "https://gateway.example/v1/models",
                                   "headers" => { "Authorization" => "Bearer test-key-not-real", "Content-Type" => "application/json" },
                                   "body" => nil)

      http, = fake_http([200, '["anthropic/claude-opus-5"]'])
      expect(client_for(http).models).to eq(["anthropic/claude-opus-5"])
      http, = fake_http([200, '{"data":[]}'])
      expect(client_for(http).models).to eq([])
    end

    it "is nil after one warn line, never raising, on a non-2xx, a request error, or a body with no list" do
      http, requests = fake_http([502, "bad gateway"])
      client = client_for(http)
      result, err = capturing_stderr { client.models }
      expect(result).to be_nil
      expect(requests.size).to eq(1) # a diagnostic: no retry
      expect(client.last_status).to eq(502)
      expect(err).to include("502", "models endpoint")
      expect(err).not_to include("test-key-not-real")
      expect(err.lines.size).to eq(1)

      http, = fake_http(SocketError.new("getaddrinfo"))
      result, err = capturing_stderr { client_for(http).models }
      expect(result).to be_nil
      expect(err).to include("SocketError")

      http, = fake_http([200, '{"object":"list"}'])
      result, err = capturing_stderr { client_for(http).models }
      expect(result).to be_nil
      expect(err).to include("no model list")
    end
  end

  describe "the Net::HTTP path" do
    # Stand-ins for Net::HTTP and its response: no socket is opened.
    FakeNetHttp = Struct.new(:response) do
      attr_accessor :use_ssl, :open_timeout, :read_timeout, :posted

      def start
        yield self
      end

      def request(post)
        self.posted = post
        response
      end
    end
    FakeNetResponse = Struct.new(:code, :body)

    it "posts over TLS with the two timeouts and the headers when no callable is injected" do
      fake = FakeNetHttp.new(FakeNetResponse.new("200", completion(reading_json)))
      allow(Net::HTTP).to receive(:new).with("api.nicrron.ai", 443).and_return(fake)
      client = described_class.new(api_key: "test-key-not-real", base_url: "https://api.nicrron.ai/v1", model: model,
                                   open_timeout: 7, read_timeout: 45)
      result = chat(client)

      expect(result).to eq("text" => reading_json, "model" => "anthropic/claude-opus-5")
      expect(fake.use_ssl).to be(true)
      expect(fake.open_timeout).to eq(7)
      expect(fake.read_timeout).to eq(45)
      expect(fake.posted).to be_a(Net::HTTP::Post)
      expect(fake.posted.path).to eq("/v1/chat/completions")
      expect(fake.posted["Authorization"]).to eq("Bearer test-key-not-real")
      expect(fake.posted["Content-Type"]).to eq("application/json")
      expect(JSON.parse(fake.posted.body)).to include("model" => "anthropic/claude-opus-5", "temperature" => 0)
    end

    it "sends a GET for the model listing" do
      fake = FakeNetHttp.new(FakeNetResponse.new("200", '{"data":[{"id":"anthropic/claude-opus-5"}]}'))
      allow(Net::HTTP).to receive(:new).with("api.nicrron.ai", 443).and_return(fake)
      client = described_class.new(api_key: "test-key-not-real", base_url: "https://api.nicrron.ai/v1", model: model)

      expect(client.models).to eq(["anthropic/claude-opus-5"])
      expect(fake.use_ssl).to be(true)
      expect(fake.posted).to be_a(Net::HTTP::Get)
      expect(fake.posted.path).to eq("/v1/models")
      expect(fake.posted["Authorization"]).to eq("Bearer test-key-not-real")
      expect(fake.posted.body).to be_nil
    end

    it "uses plain HTTP, port 80, and the default timeouts for an http base url" do
      fake = FakeNetHttp.new(FakeNetResponse.new("200", completion(reading_json)))
      allow(Net::HTTP).to receive(:new).with("localhost", 8080).and_return(fake)
      client = described_class.new(api_key: "k", base_url: "http://localhost:8080/v1", model: model)
      chat(client)

      expect(fake.use_ssl).to be(false)
      expect(fake.open_timeout).to eq(10)
      expect(fake.read_timeout).to eq(90)
    end
  end
end
