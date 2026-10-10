require "digest"
require "time"

module DistributorPricing
  module LineValidity
    def self.fingerprint(line)
      Digest::SHA256.hexdigest(JSON.generate([line.original_text, line.catalog_sku, line.quantity&.to_s("F"),
        line.quantity_unit, line.unit_price&.to_s("F"), line.price_source, line.spec.sort.to_h]))
    end

    def self.goods_fingerprint(line)
      Digest::SHA256.hexdigest(JSON.generate([line.original_text, line.catalog_sku, line.quantity&.to_s("F"), line.quantity_unit, line.spec.sort.to_h]))
    end

    def self.current?(line, now: Time.current)
      metadata = line.processing
      return true unless metadata.is_a?(Hash) && metadata.key?("distributor_pricing")
      price = metadata["distributor_pricing"]
      return false unless price.is_a?(Hash) && Time.iso8601(price.fetch("valid_until")) > now
      values_current = if line.rep_entered_price? && Array(line.edited_fields).include?("unit_price")
        price["goods_fingerprint"] == goods_fingerprint(line) && manual_margin_valid?(line, price)
      else
        price["fingerprint"] == fingerprint(line)
      end
      return false unless values_current
      # A belongs_to cache can retain an old source after another controller
      # updates the RFQ. Check persisted source values, not that cached object.
      source = Quote.where(id: line.quote_id).pick(:source_text, :original_filename, :source_bytes)
      latest = PricingRun.where(quote_id: line.quote_id).order(id: :desc).pick(:id, :status)
      source && latest == [price["run_id"], "succeeded"] && price["source_digest"] == Run.source_digest_values(*source)
    rescue ArgumentError, KeyError, TypeError
      false
    end

    def self.manual_margin_valid?(line, evidence)
      revenue = (line.unit_price * line.quantity).round(2)
      cost = BigDecimal(evidence.fetch("cost_before_payment_fee").to_s)
      fee_rate = BigDecimal(evidence.fetch("payment_fee_rate").to_s)
      fee = (revenue * fee_rate).round(2, BigDecimal::ROUND_CEILING)
      revenue.positive? && cost.finite? && cost >= 0 && fee_rate.finite? && fee_rate >= 0 &&
        (revenue - cost - fee) / revenue >= BigDecimal("0.08")
    rescue KeyError, ArgumentError, TypeError, NoMethodError
      false
    end
  end
end
