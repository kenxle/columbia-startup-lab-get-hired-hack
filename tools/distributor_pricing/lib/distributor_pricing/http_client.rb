# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require "resolv"
require "ipaddr"
require "time"
require "open3"

module DistributorPricing
  # Reads public evidence only. DNS addresses are checked and pinned for the connection.
  class HttpClient
    DEFAULT_HOSTS = %w[fred.stlouisfed.org www.aircraftspruce.com www.wicksaircraft.com].freeze
    BLOCKED_V4 = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4].map { |range| IPAddr.new(range) }.freeze
    BLOCKED_V6 = %w[2001::/23 2001:db8::/32 2002::/16 3fff::/20].map { |range| IPAddr.new(range) }.freeze
    GLOBAL_V6 = IPAddr.new("2000::/3")
    REDIRECTS = [301, 302, 303, 307, 308].freeze

    class FetchError < StandardError
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    def initialize(allowed_hosts: DEFAULT_HOSTS, open_timeout: 8, read_timeout: 15,
                   max_bytes: 3_000_000, max_redirects: 3, resolver: nil, http_factory: nil,
                   clock: -> { Time.now.utc })
      @allowed_hosts = Array(allowed_hosts).map { |host| host.to_s.downcase }.freeze
      @open_timeout, @read_timeout = Float(open_timeout), Float(read_timeout)
      @max_bytes, @max_redirects = Integer(max_bytes), Integer(max_redirects)
      unless @open_timeout.finite? && @read_timeout.finite? && @open_timeout.positive? && @read_timeout.positive? && @max_bytes.positive? && @max_bytes <= 3_000_000 && @max_redirects >= 0
        raise ArgumentError, "finite positive timeouts and a size limit up to 3 MB are required"
      end

      @resolver = resolver || lambda do |host|
        Resolv::DNS.open do |dns|
          dns.timeouts = [3, 3]
          dns.getaddresses(host).map(&:to_s)
        end
      end
      # Explicit nil proxy disables environment-provided proxy bypass of pinned DNS.
      @http_factory = http_factory || ->(host, port) { Net::HTTP.new(host, port, nil) }
      native_curl = File.join(ENV.fetch("SystemRoot", "C:/Windows"), "System32", "curl.exe")
      @native_curl = native_curl if RUBY_PLATFORM.match?(/mingw|mswin/) && http_factory.nil? && File.file?(native_curl)
      @clock = clock
    end

    def get(url)
      original = url
      redirects = 0
      loop do
        uri = safe_uri(url)
        addresses = Array(@resolver.call(uri.hostname)).map(&:to_s)
        raise FetchError.new("dns_error", "Supplier host did not resolve.") if addresses.empty?
        unless addresses.all? { |address| public_address?(address) }
          raise FetchError.new("unsafe_address", "Host resolves to a private, local or reserved address.")
        end

        response = request(uri, addresses.first)
        status = response.fetch("status")
        if REDIRECTS.include?(status)
          raise FetchError.new("redirect_limit", "Source exceeded the redirect limit.") if redirects >= @max_redirects
          raise FetchError.new("invalid_redirect", "Source redirect has no location.") if response["location"].to_s.empty?

          url = URI.join(uri.to_s, response["location"]).to_s
          redirects += 1
          next
        end
        raise FetchError.new("http_error", "Source returned HTTP #{status}.") unless status == 200

        return { "ok" => true, "url" => uri.to_s, "requested_url" => original, "status" => status,
                 "body" => response["body"], "content_type" => response["content_type"], "retrieved_at" => @clock.call.utc.iso8601 }
      end
    rescue FetchError => error
      failure(original, error.code, error.message)
    rescue URI::InvalidURIError, ArgumentError => error
      failure(original, "invalid_url", error.message)
    rescue OpenSSL::SSL::SSLError
      failure(original, "tls_error", "Source TLS certificate or secure connection could not be verified.")
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
      failure(original, "timeout", "Source did not respond within the configured timeout.")
    rescue SocketError, Resolv::ResolvError, IOError, SystemCallError, EOFError, Net::HTTPBadResponse, Net::ProtocolError => error
      failure(original, "network_error", "Source could not be retrieved (#{error.class}).")
    end

    # Credentials only go to the caller's explicitly allowed HTTPS host.
    # Authenticated requests do not follow redirects to another endpoint.
    def post_json(url, payload, token:)
      require "json"
      raise FetchError.new("invalid_token", "Gateway token is missing or invalid.") unless token.is_a?(String) && !token.empty? && !token.match?(/[\r\n"\\]/)
      uri = safe_uri(url)
      addresses = Array(@resolver.call(uri.hostname)).map(&:to_s)
      raise FetchError.new("unsafe_address", "Gateway host does not resolve exclusively to public addresses.") if addresses.empty? || !addresses.all? { |address| public_address?(address) }
      response = request(uri, addresses.first, payload: JSON.generate(payload), token: token)
      raise FetchError.new("http_error", "Gateway returned HTTP #{response['status']}.") unless response["status"] == 200
      { "ok" => true, "body" => response["body"], "url" => url, "retrieved_at" => @clock.call.utc.iso8601 }
    rescue StandardError => error
      message = error.is_a?(FetchError) ? error.message : "Gateway request failed (#{error.class}); credentials and request content are not logged."
      failure(url, error.respond_to?(:code) ? error.code : "gateway_error", message)
    end

    private

    def safe_uri(url)
      raise FetchError.new("invalid_url", "Source URL must be a string.") unless url.is_a?(String)

      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil? && @allowed_hosts.include?(uri.hostname&.downcase)
        raise FetchError.new("disallowed_url", "Source must use HTTPS on an explicitly allowed host without credentials or fragments.")
      end
      uri
    end

    def public_address?(address)
      ip = IPAddr.new(address)
      return BLOCKED_V4.none? { |range| range.include?(ip) } if ip.ipv4?

      GLOBAL_V6.include?(ip) && BLOCKED_V6.none? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      false
    end

    def request(uri, address, payload: nil, token: nil)
      return native_request(uri, address, payload: payload, token: token) if @native_curl

      http = @http_factory.call(uri.hostname, uri.port)
      http.ipaddr = address
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.verify_hostname = true
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.write_timeout = @read_timeout
      http.max_retries = 0
      request_class = payload ? Net::HTTP::Post : Net::HTTP::Get
      request = request_class.new(uri.request_uri,
                                   "User-Agent" => "RudCo-Quote-Research/1.0",
                                   "Accept" => "*/*", "Accept-Encoding" => "identity",
                                   "Cache-Control" => "no-cache, no-store", "Pragma" => "no-cache")
      if payload
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{token}"
        request.body = payload
      end
      result = nil
      http.start do |session|
        session.request(request) do |response|
          result = { "status" => response.code.to_i, "location" => response["location"], "content_type" => response["content-type"] }
          next unless result["status"] == 200

          content_length = response["content-length"]
          raise FetchError.new("response_too_large", "Source exceeds the maximum response size.") if content_length && content_length.to_i > @max_bytes

          body = +"".b
          response.read_body do |chunk|
            raise FetchError.new("response_too_large", "Source exceeds the maximum response size.") if body.bytesize + chunk.bytesize > @max_bytes

            body << chunk
          end
          result["body"] = body
        end
      end
      result
    end

    # Windows' native TLS transport works with the host certificate store.
    # Arguments are passed without a shell; DNS remains pinned and redirects
    # remain handled by get(), with the same host and size checks.
    def native_request(uri, address, payload: nil, token: nil)
      args = [@native_curl, "--disable", "--proxy", "", "--noproxy", "*",
        "--silent", "--show-error", "--include", "--proto", "=https",
        "--connect-timeout", @open_timeout.to_s, "--max-time", (@open_timeout + @read_timeout).to_s,
        "--max-filesize", @max_bytes.to_s, "--max-redirs", "0",
        "--resolve", "#{uri.hostname}:443:#{address}",
        "--header", "Cache-Control: no-cache, no-store", "--header", "Pragma: no-cache",
        "--url", uri.to_s]
      # The token and RFQ are passed via private stdin, never process arguments.
      config = ""
      if payload
        args += ["--config", "-"]
        escaped = payload.gsub(/[\\"]/) { |character| "\\#{character}" }
        config = "request = \"POST\"\nheader = \"Content-Type: application/json\"\nheader = \"Authorization: Bearer #{token}\"\ndata = \"#{escaped}\"\n"
      end
      stdout, _stderr, status = Open3.capture3(*args, stdin_data: config)
      raise FetchError.new(status.exitstatus == 28 ? "timeout" : "network_error", "Native HTTPS source retrieval failed.") unless status.success?
      headers, body = stdout.split(/\r?\n\r?\n/, 2)
      # Informational HTTP responses can precede the final header block.
      while body&.start_with?("HTTP/")
        headers, body = body.split(/\r?\n\r?\n/, 2)
      end
      raise FetchError.new("invalid_response", "Source returned invalid HTTPS headers.") unless headers&.match?(/\AHTTP\/[\d.]+ \d{3}/)
      body ||= ""
      raise FetchError.new("response_too_large", "Source exceeds the maximum response size.") if body.bytesize > @max_bytes
      values = headers.lines.drop(1).filter_map { |line| line.include?(":") ? line.split(":", 2).map(&:strip) : nil }.to_h.transform_keys(&:downcase)
      { "status" => headers.lines.first.split[1].to_i, "location" => values["location"], "content_type" => values["content-type"], "body" => body }
    end

    def failure(url, code, message)
      { "ok" => false, "url" => url, "body" => nil, "retrieved_at" => @clock.call.utc.iso8601,
        "error" => { "code" => code, "message" => message } }
    end
  end
end
