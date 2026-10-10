# frozen_string_literal: true

require "json"
require "uri"
require "time"
require_relative "http_client"

module DistributorPricing
  # Optional registered procurement feed, configured by the server/operator,
  # never by buyer text. It must query supplier/checkout terms for this request.
  class SupplierFeed
    def initialize(endpoint:, http_client: nil, clock: -> { Time.now.utc })
      @endpoint, @clock = endpoint, clock
      uri = URI(endpoint)
      raise ArgumentError, "Procurement endpoint must be HTTPS" unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.fragment.nil?
      raise ArgumentError, "An LLM gateway is not a procurement source" if %w[api.nicrron.ai nicrron.ai ninoo.ai].include?(uri.hostname.to_s.downcase)
      @http = http_client || HttpClient.new(allowed_hosts: [uri.hostname])
    end

    def refresh(request:)
      uri = URI(@endpoint)
      query = URI.decode_www_form(uri.query.to_s)
      query += [["request_id", request.fetch("request_id")], ["request", JSON.generate(request.reject { |key, _| key == "rfq_text" })]]
      uri.query = URI.encode_www_form(query)
      response = @http.get(uri.to_s)
      return { "ok" => false, "error" => response["error"], "lines" => {} } unless response["ok"]
      payload = JSON.parse(response.fetch("body"))
      checked = Time.iso8601(payload.fetch("checked_at"))
      start = Time.iso8601(request.fetch("started_at"))
      unless payload["request_id"] == request["request_id"] && checked >= start && checked <= @clock.call.utc
        raise ArgumentError, "feed freshness proof failed"
      end
      raise ArgumentError, "invalid feed lines" unless payload["lines"].is_a?(Hash)
      { "ok" => true, "request_id" => payload["request_id"], "checked_at" => checked.iso8601,
        "lines" => payload["lines"], "source_url" => @endpoint }
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError
      { "ok" => false, "error" => "Procurement feed did not prove same-request verification; no prior quote was reused.", "lines" => {} }
    end
  end
end
