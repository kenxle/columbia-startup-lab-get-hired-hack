module DistributorPricing
  module QuoteValidity
    def approved?
      super && quote_lines.all? { |line| LineValidity.current?(line) }
    end

    def approvable?
      super && quote_lines.all? { |line| LineValidity.current?(line) }
    end
  end
end
