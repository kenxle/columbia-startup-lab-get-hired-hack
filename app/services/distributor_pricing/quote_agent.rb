require Rails.root.join("tools/distributor_pricing/lib/distributor_pricing/agent").to_s

module DistributorPricing
  # Side-effect-free Rails entry point. Yuval remains the result assembler;
  # applying a priced line and human approval use the existing app handoff.
  class QuoteAgent
    def self.call(rfq:, destination: nil, **options)
      Agent.configured(root: Rails.root.to_s).call(rfq: rfq, destination: destination, **options)
    end
  end
end
