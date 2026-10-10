# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RfqProcessing
  # Official contract: https://docs.typesafe.ai/api and /primitives/noul.
  # One optional request, no retry. Failures never expose response bodies or keys.
  class JevClient
    ENDPOINT = URI("https://api.typesafe.ai/v1/systemone").freeze
    MODEL = "jev-latest"
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 3
    WRITE_TIMEOUT = 3
    MAX_BODY_BYTES = 65_536
    MAX_QUESTIONS = 4

    attr_reader :model

    def self.from_env(env: ENV)
      key = env["JEV_API_KEY"].to_s.strip
      return nil if key.empty?

      new(api_key: key, model: env.fetch("JEV_MODEL", MODEL))
    end

    # http is an offline transport seam, callable with a Net::HTTP::Post.
    def initialize(api_key:, model: MODEL, http: nil)
      @api_key = api_key.to_s
      @model = model.to_s
      @http = http
    end

    def evaluate(state:, questions:)
      return nil if @api_key.strip.empty? || !@model.match?(/\Ajev-(?:latest|\d+\.\d+\.\d+)\z/)
      return nil unless questions.is_a?(Hash) && questions.size.between?(1, MAX_QUESTIONS)

      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate("model" => @model, "state" => state, "questions" => questions)
      code, body = @http ? @http.call(request) : send_request(request)
      return nil unless code.to_i == 200 && body.is_a?(String) && body.bytesize <= MAX_BODY_BYTES

      response = JSON.parse(body)
      return nil unless response.is_a?(Hash) && matching_model?(response["model"])
      answers = response["answers"]
      return nil unless answers.is_a?(Hash) && answers.keys.sort == questions.keys.sort
      valid = answers.values.all? do |answer|
        value = answer.is_a?(Hash) && answer["noul"]
        answer.is_a?(Hash) && answer["type"] == "noul" && value.is_a?(Numeric) && value.finite? && value.between?(0, 1)
      end
      return nil unless valid

      { "model" => response["model"], "probabilities" => answers.transform_values { |answer| answer["noul"] } }
    rescue StandardError
      nil
    end

    private

    def matching_model?(answered)
      answered.is_a?(String) && (answered == @model || (@model == MODEL && answered.match?(/\Ajev-\d+\.\d+\.\d+\z/)))
    end

    def send_request(request)
      http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.write_timeout = WRITE_TIMEOUT
      http.max_retries = 0
      code = nil
      body = +""
      http.start do |connection|
        connection.request(request) do |response|
          code = response.code.to_i
          response.read_body do |chunk|
            raise IOError if body.bytesize + chunk.bytesize > MAX_BODY_BYTES
            body << chunk
          end
        end
      end
      [code, body]
    end
  end
end
