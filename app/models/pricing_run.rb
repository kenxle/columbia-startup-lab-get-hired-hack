require "uri"

class PricingRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed stale].freeze
  ACTIVE_STATUSES = %w[queued running].freeze
  MAXIMUM_RESULT_BYTES = 2_000_000

  belongs_to :quote
  validates :status, inclusion: { in: STATUSES }
  validates :source_revision, :source_digest, :queued_at, presence: true
  validates :source_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :error_message, length: { maximum: 1_000 }
  validate :destination_shape
  validate :result_shape

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def current_for?(record)
    [source_revision, applied_revision].compact.include?(record.review_revision) && source_digest == DistributorPricing::Run.source_digest(record)
  end

  def output_available?(record)
    status == "succeeded" && current_for?(record)
  end

  def quote_prices_current?(record, now: Time.current)
    return false unless output_available?(record)
    return false unless result.dig("quote", "total").present?
    Time.iso8601(result.dig("quote", "valid_until")) > now
  rescue ArgumentError, TypeError
    false
  end

  def self.safe_source_url(value)
    return unless value.is_a?(String) && value.bytesize <= 2_000
    uri = URI.parse(value)
    return unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.port == 443
    return if value.match?(/[\x00-\x20\x7f]/)
    value
  rescue URI::InvalidURIError
    nil
  end

  # The engine owns pricing eligibility. Persistence additionally requires a
  # bounded, inert audit and refuses a ready line missing its core evidence.
  def self.valid_result?(value)
    return false unless value.is_a?(Hash) && value["schema"] == "distributor_pricing/v1"
    lines = value["lines"]
    return false unless lines.is_a?(Array) && lines.length.between?(0, 100)
    remaining = 100_000
    inspect_value = lambda do |entry, depth|
      remaining -= 1
      return false if remaining.negative? || depth > 24
      case entry
      when Hash
        entry.all? { |key, child| key.is_a?(String) && key.bytesize <= 200 && !key.match?(/api.?key|authorization|access.?token|secret/i) && inspect_value.call(child, depth + 1) }
      when Array
        entry.all? { |child| inspect_value.call(child, depth + 1) }
      when String
        entry.valid_encoding? && entry.bytesize <= 100_000
      when Integer, TrueClass, FalseClass, NilClass
        true
      when Float
        entry.finite?
      else
        false
      end
    end
    return false unless inspect_value.call(value, 0) && JSON.generate(value).bytesize <= MAXIMUM_RESULT_BYTES
    return false unless value["quote"].is_a?(Hash)
    lines.all? do |line|
      next false unless line.is_a?(Hash) && line["pricing"].is_a?(Hash)
      price = line["pricing"]
      next true unless price["status"] == "ready"
      unit_price = BigDecimal(price.fetch("unit_price").to_s)
      margin = BigDecimal(price.dig("pricing_analysis", "realized_margin").to_s)
      offer = price.dig("procurement_plan", "supplier_offer_evidence")
      unit_price.finite? && unit_price.positive? && margin.finite? && margin >= BigDecimal("0.08") &&
        Time.iso8601(price.fetch("quote_valid_until")) > Time.iso8601(value.fetch("calculated_at")) &&
        price.dig("pricing_analysis", "independent_benchmark_suppliers").is_a?(Integer) &&
        price.dig("pricing_analysis", "independent_benchmark_suppliers") >= 5 &&
        price["cost_breakdown"].is_a?(Hash) && offer.is_a?(Hash) &&
        safe_source_url(offer["source_url"]).present?
    end
  rescue JSON::GeneratorError, EncodingError, ArgumentError, KeyError, TypeError
    false
  end

  private

  def destination_shape
    unless destination.is_a?(Hash) && destination.keys.sort == %w[country postal_code] &&
        destination["country"].is_a?(String) && destination["country"].match?(/\A[A-Z]{2}\z/) &&
        destination["postal_code"].is_a?(String) && destination["postal_code"].match?(/\A[A-Za-z0-9][A-Za-z0-9 -]{0,19}\z/)
      errors.add(:destination, "requires a two-letter country and postal code")
    end
  end

  def result_shape
    errors.add(:result, "must contain bounded pricing evidence") if result && !self.class.valid_result?(result)
  end
end
