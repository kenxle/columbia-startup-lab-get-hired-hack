# frozen_string_literal: true

require "bigdecimal"

module DistributorPricing
  # These are quoting controls, not inferred supplier costs.
  class Policy
    attr_reader :target_margin, :minimum_margin, :max_source_age_seconds, :quote_validity_seconds, :minimum_benchmark_suppliers

    def initialize(target_margin: "0.15", minimum_margin: "0.08",
                   max_source_age_seconds: 86_400, quote_validity_seconds: 86_400, minimum_benchmark_suppliers: 5)
      @target_margin = BigDecimal(target_margin.to_s)
      @minimum_margin = BigDecimal(minimum_margin.to_s)
      unless @target_margin.finite? && @minimum_margin.finite? &&
             @minimum_margin >= 0 && @minimum_margin <= @target_margin && @target_margin < 1
        raise ArgumentError, "margins must satisfy 0 <= minimum <= target < 1"
      end
      @max_source_age_seconds = Integer(max_source_age_seconds)
      @quote_validity_seconds = Integer(quote_validity_seconds)
      raise ArgumentError, "validity windows must be positive" unless @max_source_age_seconds.positive? && @quote_validity_seconds.positive?
      @minimum_benchmark_suppliers = Integer(minimum_benchmark_suppliers)
      raise ArgumentError, "At least two independent benchmark suppliers are required" unless @minimum_benchmark_suppliers >= 2

      freeze
    end

    def to_h
      { "target_margin" => target_margin.to_s("F"), "minimum_margin" => minimum_margin.to_s("F"),
        "max_source_age_seconds" => max_source_age_seconds, "quote_validity_seconds" => quote_validity_seconds,
        "minimum_benchmark_suppliers" => minimum_benchmark_suppliers }
    end
  end
end
