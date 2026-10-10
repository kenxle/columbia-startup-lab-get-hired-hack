# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "securerandom"

module RfqProcessing
  # A small chat completions client for OpenAI-compatible gateways: the hackathon's
  # Nicrron gateway in front of Claude. Standard library only, Net::HTTP and JSON.
  #
  # One call is one POST to <base_url>/chat/completions with a strict json_schema
  # response_format. A 400/422 rejecting the schema format is retried
  # once without response_format, with the schema
  # written into the system message. A 502, 503, or 504 is read as a flaky gateway:
  # the same request is sent once more after a short pause. Nothing here raises;
  # every failure is one warn line and nil, so the pipeline keeps the rules reading.
  # The API key travels in the Authorization header and is never written to a log line.
  class OpenAiCompatibleClient
    TRANSIENT_STATUSES = [502, 503, 504].freeze
    TRANSIENT_PAUSE_SECONDS = 1
    SCHEMA_NAME = "rfq_line"
    PLAIN_JSON_INSTRUCTION = "Answer with exactly one JSON object and nothing else, matching this JSON schema:"

    # Metadata-only hook shared with the app's PRISM listener. Disabled by
    # default; one event for each actual inference HTTP attempt, not /models.
    class << self
      attr_accessor :trace_listener
    end

    attr_reader :base_url, :model, :last_status

    # http: a callable for tests, ->(request) { [status, body_string] }, where request is a Hash
    # with string keys "method" ("POST" or "GET"), "url", "headers", and "body" (the body as a
    # Hash, nil for a GET). Nil means Net::HTTP.
    def initialize(api_key:, base_url:, model:, open_timeout: 10, read_timeout: 90, http: nil, trace_listener: nil, session_id: nil, run_id: nil)
      @api_key = api_key.to_s
      @base_url = base_url.to_s.strip.sub(%r{/+\z}, "")
      @model = model.to_s
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @http = http || method(:over_net_http)
      @last_status = nil
      @trace_listener = trace_listener
      @session_id = trace_uuid(session_id)
      @run_id = trace_uuid(run_id)
    end

    def url
      "#{@base_url}/chat/completions"
    end

    def models_url
      "#{@base_url}/models"
    end

    # { "text" => the assistant message content, "model" => the model the gateway names, or nil }.
    # Nil on any failure, after one warn line.
    def chat(system:, user:, schema:, max_tokens:)
      trace_run_id = @run_id || SecureRandom.uuid
      status, raw = post(structured_body(system, user, schema, max_tokens), run_id: trace_run_id)
      return nil if status.nil?

      if schema_rejected?(status, raw)
        first = status
        status, raw = post(plain_body(system, user, schema, max_tokens), run_id: trace_run_id)
        return nil if status.nil?

        unless success?(status)
          warn "OpenAiCompatibleClient: chat endpoint answered #{first} with response_format, then #{status} without it; no reading"
          return nil
        end
        warn "OpenAiCompatibleClient: chat endpoint rejected response_format (#{first}); the retry with the schema in the system message succeeded"
      elsif !success?(status)
        warn "OpenAiCompatibleClient: chat endpoint answered #{status}"
        return nil
      end
      extract(raw)
    rescue StandardError => e
      warn "OpenAiCompatibleClient: request to chat endpoint failed (#{e.class})"
      nil
    end

    # The model ids the gateway lists at GET <base_url>/models (the OpenAI shape, {"data" => [{"id" => ...}]},
    # or a bare array). A diagnostic: one request, no retry, so a flaky answer shows as it is.
    # Nil after one warn line when the answer is not 2xx, the request fails, or the body has no list.
    def models
      status, raw = send_once("GET", models_url, nil)
      unless success?(status)
        warn "OpenAiCompatibleClient: GET models endpoint answered #{status}"
        return nil
      end
      parsed = JSON.parse(raw)
      list = parsed.is_a?(Hash) ? parsed["data"] : parsed
      unless list.is_a?(Array)
        warn "OpenAiCompatibleClient: GET models endpoint answered 2xx with no model list"
        return nil
      end
      list.filter_map { |entry| entry.is_a?(Hash) ? entry["id"] : entry }.map(&:to_s).reject(&:empty?)
    rescue StandardError => e
      warn "OpenAiCompatibleClient: GET models endpoint failed (#{e.class})"
      nil
    end

    private

    def schema_rejected?(status, raw)
      [400, 422].include?(status) && raw.to_s.match?(/response_format|json_schema/i)
    end

    # [status, body] after at most one same-request retry on a transient status.
    # Nil when the retry is transient too, after the one warn line.
    def post(body, run_id:)
      status, raw = send_once("POST", url, body, run_id: run_id)
      return [status, raw] unless TRANSIENT_STATUSES.include?(status)

      sleep(TRANSIENT_PAUSE_SECONDS)
      status, raw = send_once("POST", url, body, run_id: run_id)
      return [status, raw] unless TRANSIENT_STATUSES.include?(status)

      warn "OpenAiCompatibleClient: chat endpoint answered #{status} twice; giving up"
      nil
    end

    def send_once(method, target, body, run_id: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @last_status = nil
      status, raw = @http.call({ "method" => method, "url" => target, "headers" => headers, "body" => body })
      @last_status = Integer(status)
      [@last_status, raw.to_s]
    ensure
      trace_attempt(started, @last_status, raw, run_id) if method == "POST"
    end

    def trace_uuid(value)
      text = value.to_s
      text if text.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
    end

    def trace_attempt(started, status, raw, run_id)
      listener = @trace_listener.nil? ? self.class.trace_listener : @trace_listener
      return unless listener && started

      # Do not reflect response model/ID strings: provider errors can echo input.
      safe_model = @model if @model.match?(/\A(?:anthropic\/)?claude-(?:opus|sonnet|haiku)-\d+(?:-\d+)*(?:@\d{8})?\z/i)
      verified = nil
      outcome = status.nil? ? "network_error" : "http_error"
      if status && success?(status)
        envelope = JSON.parse(raw.to_s) rescue nil
        returned = envelope.is_a?(Hash) && envelope["model"]
        if !envelope.is_a?(Hash)
          outcome = "invalid_response"
        elsif !returned.is_a?(String) || returned.strip.empty?
          outcome = "model_identity_missing"
          verified = false
        else
          expected = @model.strip.downcase.sub(%r{\A[^/]+/}, "")
          actual = returned.strip.downcase.sub(%r{\A[^/]+/}, "")
          verified = !expected.empty? && (actual == expected || actual.match?(/\A#{Regexp.escape(expected)}[-@]\d{8}\z/))
          outcome = verified ? "http_success" : "model_mismatch"
        end
      end
      event = { model: safe_model, elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
                      outcome: outcome, request_id: SecureRandom.uuid, run_id: run_id, session_id: @session_id,
                      http_status: status, returned_model_verified: verified }.freeze
      listener.call(**event)
    rescue StandardError
      nil # Telemetry must never affect a request or disclose listener errors.
    end

    def headers
      { "Authorization" => "Bearer #{@api_key}", "Content-Type" => "application/json" }
    end

    def structured_body(system, user, schema, max_tokens)
      base_body(system, user, max_tokens).merge(
        "response_format" => { "type" => "json_schema",
                               "json_schema" => { "name" => SCHEMA_NAME, "strict" => true, "schema" => schema } }
      )
    end

    def plain_body(system, user, schema, max_tokens)
      base_body("#{system.to_s.rstrip}\n\n#{PLAIN_JSON_INSTRUCTION}\n#{JSON.generate(schema)}", user, max_tokens)
    end

    def base_body(system, user, max_tokens)
      { "model" => @model,
        "messages" => [{ "role" => "system", "content" => system.to_s }, { "role" => "user", "content" => user.to_s }],
        "max_tokens" => max_tokens,
        "temperature" => 0 }
    end

    def extract(raw)
      parsed = JSON.parse(raw)
      choice = parsed.is_a?(Hash) && parsed["choices"].is_a?(Array) ? parsed["choices"][0] : nil
      message = choice.is_a?(Hash) ? choice["message"] : nil
      content = message.is_a?(Hash) ? message["content"] : nil
      content = content.map { |part| part.is_a?(Hash) ? part["text"].to_s : part.to_s }.join if content.is_a?(Array)
      if !content.is_a?(String) || content.strip.empty?
        warn "OpenAiCompatibleClient: chat endpoint answered with no choices[0].message.content"
        return nil
      end
      { "text" => content, "model" => (parsed["model"].is_a?(String) ? parsed["model"] : nil) }
    rescue JSON::ParserError
      warn "OpenAiCompatibleClient: chat endpoint answered 2xx with a body that is not JSON"
      nil
    end

    def success?(status)
      (200..299).cover?(status)
    end

    def over_net_http(request)
      uri = URI.parse(request["url"])
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      call = if request["method"] == "GET"
               Net::HTTP::Get.new(uri.request_uri, request["headers"])
             else
               post = Net::HTTP::Post.new(uri.request_uri, request["headers"])
               post.body = JSON.generate(request["body"])
               post
             end
      response = http.start { |connection| connection.request(call) }
      [response.code.to_i, response.body.to_s]
    end
  end
end
