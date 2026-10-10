module DistributorPricing
  module QuoteLineValidity
    def quotable?
      super && LineValidity.current?(self)
    end
  end
end
