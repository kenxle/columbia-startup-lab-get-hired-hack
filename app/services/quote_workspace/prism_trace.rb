require "net/http"
require "json"
require "securerandom"

module QuoteWorkspace
  # Optional metadata-only telemetry. Prompts, replies and buyer data are never accepted.
  class PrismTrace
    ENDPOINT = URI("https://prism.blockconvey.com/api/traces").freeze
    OUTCOMES = %w[ok gateway_error unparseable error synthetic_smoke].freeze
    RATE_LOCK = Mutex.new
    MAX_PER_MINUTE = 20
    RUN_UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def self.configured?(env = ENV)
      %w[PRISMTRACE_API_KEY PRISMTRACE_PROJECT_ID].all? { |key| !env[key].to_s.strip.empty? }
    end

    def self.enqueue(event)
      return false unless configured?
      return false if PrismTraceJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter)
      permitted = RATE_LOCK.synchronize do
        minute = Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i / 60
        @count = 0 if @minute != minute
        @minute = minute
        @count = (@count || 0) + 1
        @count <= MAX_PER_MINUTE
      end
      return false unless permitted

      PrismTraceJob.perform_later(sanitize(event))
      true
    rescue StandardError
      false
    end

    def self.sanitize(event)
      event = event.to_h.transform_keys(&:to_s)
      model = event["model"].to_s
      model = "unknown-model" unless model.match?(/\A(?:anthropic\/)?claude-[a-zA-Z0-9.@_-]{1,80}\z/)
      outcome = OUTCOMES.include?(event["outcome"].to_s) ? event["outcome"].to_s : "error"
      elapsed = Float(event["elapsed_ms"].to_s, exception: false)
      elapsed = elapsed && elapsed.finite? ? [[elapsed, 0].max, 600_000].min.round : 0
      sanitized = { "model" => model, "outcome" => outcome, "elapsed_ms" => elapsed }
      run_id = event["run_id"]
      sanitized["run_id"] = run_id.downcase if run_id.is_a?(String) && run_id.match?(RUN_UUID)
      sanitized
    end

    def self.call(event, env: ENV, http: nil)
      return { status: "disabled" } unless configured?(env)
      event = sanitize(event)
      run_id = event["run_id"] || SecureRandom.uuid
      payload = {
        project_id: env.fetch("PRISMTRACE_PROJECT_ID"), model: event.fetch("model"),
        input_messages: [{ role: "user", content: "Synthetic metadata envelope only. Original RFQ input is intentionally omitted." }],
        output_message: "Metadata only, not model output: #{JSON.generate(event)}",
        latency_ms: event.fetch("elapsed_ms"), agent_id: "rudco-quote-desk-metadata",
        session_id: "metadata-#{run_id}",
        metadata: { content_redacted: true, synthetic_message_envelope: true, outcome: event.fetch("outcome"), run_id: run_id }
      }
      request = Net::HTTP::Post.new(ENDPOINT)
      request["Content-Type"] = "application/json"
      request["X-PRISMtrace-Key"] = env.fetch("PRISMTRACE_API_KEY")
      request.body = JSON.generate(payload)
      transport = http || Net::HTTP.new(ENDPOINT.host, ENDPOINT.port).tap do |client|
        client.use_ssl = true
        client.open_timeout = 2
        client.read_timeout = 3
        client.write_timeout = 3
      end
      response = transport.request(request)
      return { status: "rejected", http_status: response.code.to_i } unless (200..299).cover?(response.code.to_i)
      parsed = JSON.parse(response.body.to_s)
      id = parsed.is_a?(Hash) && parsed["id"]
      return { status: "unconfirmed" } unless id.is_a?(String) && id.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)

      { status: "accepted", trace_id: id }
    rescue StandardError
      { status: "failed" }
    end
  end
end
