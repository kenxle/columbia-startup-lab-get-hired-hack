# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require_relative "../lib/distributor_pricing/market_context"

class DistributorPricingMarketContextTest < Minitest::Test
  NOW = Time.utc(2026, 10, 10, 18)

  class StubClient
    attr_reader :calls
    attr_accessor :response, :rows

    def initialize
      @calls = []
      @rows = "2026-07-01,100\n2026-08-01,110\n"
    end

    def get(url)
      @calls << url
      return response if response

      id = URI.decode_www_form(URI(url).query).to_h.fetch("id")
      { "ok" => true, "body" => "observation_date,#{id}\n#{rows}" }
    end
  end

  def setup
    @client = StubClient.new
    @context = DistributorPricing::MarketContext.new(http_client: @client, clock: -> { NOW })
  end

  def test_fetches_both_official_series_and_keeps_publication_date_distinct
    snapshot = @context.refresh
    steel = snapshot.dig("series", "WPU1017")
    assert_equal 2, @client.calls.size
    assert_equal "https://fred.stlouisfed.org/graph/fredgraph.csv?id=WPU1017", @client.calls.first
    assert_equal "available", steel["status"]
    assert_equal "2026-08-01", steel["observation_date"]
    assert_equal NOW.iso8601, steel["refreshed_at"]
    assert_equal "110.0", steel["value"]
    assert_equal "100.0", steel["prior_value"]
    assert_equal "10.0", steel["change_pct"]
    assert_equal "Index 1982=100", steel["units"]
    assert_equal false, steel["is_finished_item_price"]
    assert_equal false, steel["is_acquisition_cost"]
    refute steel.key?("unit_price")
    refute steel.key?("currency")
  end

  def test_every_refresh_fetches_again_and_never_reuses_success_after_failure
    assert_equal "available", @context.refresh.dig("series", "WPU1017", "status")
    @client.response = { "ok" => false, "error" => { "code" => "timeout", "message" => "failed" } }
    snapshot = @context.refresh
    assert_equal 4, @client.calls.size
    assert_equal "unavailable", snapshot.dig("series", "WPU1017", "status")
    assert_nil snapshot.dig("series", "WPU1017", "value")
    assert_equal "timeout", snapshot.dig("series", "WPU1017", "error", "code")
  end

  def test_repeated_for_item_calls_without_snapshot_fetch_again
    2.times { @context.for_item({ "material" => "carbon steel" }) }
    assert_equal 4, @client.calls.size
  end

  def test_snapshot_supports_multiple_lines_in_one_refresh_run
    snapshot = @context.refresh
    steel = @context.for_item({ "specs" => { "material" => "stainless steel" } }, snapshot: snapshot)
    aluminum = @context.for_item({ "material" => "aluminium" }, snapshot: snapshot)
    assert_equal "WPU1017", steel["series_id"]
    assert_equal "WPU102501", aluminum["series_id"]
    assert_equal 2, @client.calls.size
  end

  def test_no_relevant_material_is_explicitly_unavailable
    %w[copper rubber].each do |material|
      result = @context.for_item({ "material" => material })
      assert_equal "unavailable", result["status"]
      assert_equal "context_unavailable", result.dig("error", "code")
    end
    assert_empty @client.calls
  end

  def test_ambiguous_material_does_not_choose_an_arbitrary_index
    assert_equal "unavailable", @context.for_item({ "material" => "steel and aluminum" })["status"]
  end

  def test_future_observation_is_rejected_without_older_fallback
    @client.rows += "2026-11-01,120\n"
    result = @context.refresh.dig("series", "WPU1017")
    assert_equal "unavailable", result["status"]
    assert_nil result["value"]
    assert_match(/Future/, result.dig("error", "message"))
  end

  def test_stale_observation_stays_stale_after_successful_live_fetch
    @client.rows = "2026-01-01,100\n2026-02-01,110\n"
    result = @context.refresh.dig("series", "WPU1017")
    assert_equal "stale", result["status"]
    assert_equal "2026-02-01", result["observation_date"]
    assert_equal NOW.iso8601, result["refreshed_at"]
    assert_equal "overdue_observation", result.dig("error", "code")
  end

  def test_latest_missing_nonfinite_and_negative_values_have_no_prior_fallback
    [".", "", "NaN", "Infinity", "-1", "0"].each do |value|
      @client.rows = "2026-07-01,100\n2026-08-01,#{value}\n"
      result = @context.refresh.dig("series", "WPU1017")
      assert_equal "unavailable", result["status"]
      assert_nil result["value"]
      assert_nil result["change_pct"]
    end
  end

  def test_no_change_signal_without_valid_prior_observation
    @client.rows = "2026-08-01,110\n"
    result = @context.refresh.dig("series", "WPU1017")
    assert_equal "available", result["status"]
    assert_nil result["prior_value"]
    assert_nil result["change_pct"]
  end

  def test_html_login_or_wrong_series_response_cannot_be_used_as_data
    @client.response = { "ok" => true, "body" => "<html>sign in</html>" }
    assert_equal "unavailable", @context.refresh.dig("series", "WPU1017", "status")
    @client.response = { "ok" => true, "body" => "observation_date,OTHER\n2026-08-01,110\n" }
    assert_equal "unavailable", @context.refresh.dig("series", "WPU1017", "status")
  end

  def test_out_of_order_observations_are_sorted_but_duplicates_rejected
    @client.rows = "2026-08-01,110\n2026-07-01,100\n"
    assert_equal "10.0", @context.refresh.dig("series", "WPU1017", "change_pct")
    @client.rows += "2026-08-01,120\n"
    assert_equal "duplicate_observation", @context.refresh.dig("series", "WPU1017", "error", "code")
  end

  def test_callable_client_and_client_exceptions_are_supported
    callable = ->(_url) { raise IOError, "failed" }
    context = DistributorPricing::MarketContext.new(http_client: callable, clock: -> { NOW })
    assert_equal "unavailable", context.refresh.dig("series", "WPU1017", "status")
  end

  def test_malformed_item_and_snapshot_fail_without_crashing
    assert_equal "unavailable", @context.for_item(nil)["status"]
    assert_equal "unavailable", @context.for_item({ "specs" => "bad" })["status"]
    assert_equal "unavailable", @context.for_item({ "material" => "steel" }, snapshot: { "series" => "bad" })["status"]
  end
end

class DistributorPricingHttpClientTest < Minitest::Test
  NOW = Time.utc(2026, 10, 10, 18)
  URL = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=WPU1017"

  class FakeResponse
    attr_reader :code

    def initialize(code: 200, headers: {}, chunks: ["data"])
      @code, @headers, @chunks = code.to_s, headers, chunks
    end

    def [](header)
      @headers[header]
    end

    def read_body
      @chunks.each { |chunk| yield chunk }
    end
  end

  class FakeHTTP
    attr_accessor :ipaddr, :use_ssl, :verify_mode, :verify_hostname, :open_timeout, :read_timeout, :write_timeout, :max_retries
    attr_reader :requests

    def initialize(response)
      @response = response
      @requests = []
    end

    def start
      yield self
    end

    def request(request)
      @requests << request
      raise @response if @response.is_a?(Exception)

      yield @response
    end
  end

  def setup
    @responses = [FakeResponse.new]
    @connections = []
    @hosts = []
    @resolver = ->(host) { @hosts << host; ["8.8.8.8"] }
  end

  def client(**options)
    factory = lambda do |_host, _port|
      connection = FakeHTTP.new(@responses.shift)
      @connections << connection
      connection
    end
    DistributorPricing::HttpClient.new(**{ resolver: @resolver, http_factory: factory, clock: -> { NOW } }.merge(options))
  end

  def test_secure_connection_pins_dns_checks_tls_and_requests_no_cache
    result = client.get(URL)
    assert result["ok"]
    assert_equal "data", result["body"]
    assert_equal NOW.iso8601, result["retrieved_at"]
    connection = @connections.first
    assert_equal "8.8.8.8", connection.ipaddr
    assert_equal true, connection.use_ssl
    assert_equal OpenSSL::SSL::VERIFY_PEER, connection.verify_mode
    assert_equal true, connection.verify_hostname
    assert_equal 0, connection.max_retries
    assert_match(/no-cache/, connection.requests.first["Cache-Control"])
    assert_equal "identity", connection.requests.first["Accept-Encoding"]
  end

  def test_private_loopback_metadata_reserved_and_mapped_addresses_block_before_connection
    %w[127.0.0.1 10.1.1.1 172.16.0.1 192.168.0.1 169.254.169.254 100.64.0.1 0.0.0.0 192.0.2.1 224.0.0.1 ::1 fe80::1 fc00::1 ::ffff:127.0.0.1 2001:db8::1 2002:7f00:1:: 2001:2::1 3fff::1].each do |address|
      result = client(resolver: ->(_host) { [address] }).get(URL)
      refute result["ok"], address
      assert_equal "unsafe_address", result.dig("error", "code"), address
    end
    assert_empty @connections
  end

  def test_mixed_public_and_private_dns_answers_are_rejected
    result = client(resolver: ->(_host) { ["8.8.8.8", "127.0.0.1"] }).get(URL)
    assert_equal "unsafe_address", result.dig("error", "code")
    assert_empty @connections
  end

  def test_http_unlisted_host_credentials_ports_and_fragments_are_rejected
    ["http://fred.stlouisfed.org/x", "https://evil.example/x", "https://user:pass@fred.stlouisfed.org/x", "https://fred.stlouisfed.org:444/x", "https://fred.stlouisfed.org/x#fragment"].each do |url|
      assert_equal "disallowed_url", client.get(url).dig("error", "code")
    end
    assert_empty @connections
  end

  def test_redirect_is_checked_again_and_unallowed_destination_not_contacted
    @responses = [FakeResponse.new(code: 302, headers: { "location" => "https://evil.example/x" })]
    assert_equal "disallowed_url", client.get(URL).dig("error", "code")
    assert_equal 1, @connections.size
    assert_equal ["fred.stlouisfed.org"], @hosts
  end

  def test_relative_redirect_stays_on_allowlisted_host_and_rechecks_dns
    @responses = [FakeResponse.new(code: 302, headers: { "location" => "/next" }), FakeResponse.new(chunks: ["final"])]
    result = client.get(URL)
    assert result["ok"]
    assert_equal "https://fred.stlouisfed.org/next", result["url"]
    assert_equal "final", result["body"]
    assert_equal 2, @hosts.size
  end

  def test_rebinding_on_redirect_is_rejected
    @responses = [FakeResponse.new(code: 302, headers: { "location" => "/next" })]
    answers = [["8.8.8.8"], ["127.0.0.1"]]
    result = client(resolver: ->(_host) { answers.shift }).get(URL)
    assert_equal "unsafe_address", result.dig("error", "code")
    assert_equal 1, @connections.size
  end

  def test_redirect_limit_is_bounded
    @responses = Array.new(4) { FakeResponse.new(code: 302, headers: { "location" => "/next" }) }
    assert_equal "redirect_limit", client.get(URL).dig("error", "code")
    assert_equal 4, @connections.size
  end

  def test_content_length_and_streaming_size_limits
    @responses = [FakeResponse.new(headers: { "content-length" => "100" })]
    assert_equal "response_too_large", client(max_bytes: 5).get(URL).dig("error", "code")
    @responses = [FakeResponse.new(chunks: ["123", "456"])]
    assert_equal "response_too_large", client(max_bytes: 5).get(URL).dig("error", "code")
  end

  def test_status_timeout_and_tls_errors_return_structured_failures
    [[FakeResponse.new(code: 503), "http_error"], [Net::ReadTimeout.new, "timeout"], [OpenSSL::SSL::SSLError.new, "tls_error"]].each do |response, expected|
      @responses = [response]
      result = client.get(URL)
      refute result["ok"]
      assert_nil result["body"]
      assert_equal expected, result.dig("error", "code")
    end
  end

  def test_repeated_fetches_have_no_response_cache
    @responses = [FakeResponse.new(chunks: ["first"]), FakeResponse.new(chunks: ["second"])]
    http = client
    assert_equal "first", http.get(URL)["body"]
    assert_equal "second", http.get(URL)["body"]
    assert_equal 2, @connections.size
  end

  def test_empty_dns_result_is_explicit_failure
    assert_equal "dns_error", client(resolver: ->(_host) { [] }).get(URL).dig("error", "code")
  end

  def test_configuration_cannot_remove_response_size_or_timeout_bounds
    assert_raises(ArgumentError) { client(max_bytes: 3_000_001) }
    assert_raises(ArgumentError) { client(open_timeout: Float::INFINITY) }
  end

  def test_malformed_http_is_structured_failure
    @responses = [Net::HTTPBadResponse.new("not HTTP")]
    assert_equal "network_error", client.get(URL).dig("error", "code")
  end

  def test_authenticated_post_validates_tls_and_never_follows_redirects
    @responses = [FakeResponse.new(code: 302, headers: { "location" => "https://evil.example/key" })]
    result = client.post_json(URL, { "text" => "SYNTHETIC RFQ" }, token: "SYNTHETIC-TOKEN")
    refute result["ok"]
    assert_equal 1, @connections.size
    assert_equal "Bearer SYNTHETIC-TOKEN", @connections.first.requests.first["Authorization"]
    assert_equal "POST", @connections.first.requests.first.method
    assert_match(/302/, result.dig("error", "message"))
    result = client.post_json(URL, {}, token: "bad\nheader")
    assert_equal "invalid_token", result.dig("error", "code")
    assert_equal 1, @connections.size
  end

  def test_native_transport_ignores_curl_config_and_proxies_and_keeps_secret_out_of_arguments
    http = client
    http.instance_variable_set(:@native_curl, "SYNTHETIC-CURL")
    observed = nil
    runner = lambda do |*args, **options|
      observed = [args, options]
      ["HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{}", "", Struct.new(:exitstatus) { def success? = true }.new(0)]
    end
    Open3.stub(:capture3, runner) do
      assert http.post_json(URL, { "text" => 'literal "quote" and \\ slash' }, token: "SYNTHETIC-SECRET")["ok"]
    end
    args, options = observed
    assert_equal "--disable", args[1]
    assert_includes args, "--noproxy"
    assert_includes args, "--resolve"
    refute args.join(" ").include?("SYNTHETIC-SECRET")
    assert_includes options[:stdin_data], "Authorization: Bearer SYNTHETIC-SECRET"
    config_value = options[:stdin_data].lines.find { |line| line.start_with?("data = ") }.delete_prefix("data = ").strip
    assert_equal 'literal "quote" and \\ slash', JSON.parse(JSON.parse(config_value))["text"]
  end
end
