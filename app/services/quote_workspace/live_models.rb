module QuoteWorkspace
  # Explicit development opt-in. Catalog-model activation has a separate,
  # unresolved provenance contract and remains disabled in IntakeMatcher.
  module LiveModels
    def self.enabled?
      Rails.env.development? && ENV["RFQ_LIVE_MODELS"] == "1"
    end

    def self.parser_argument
      enabled? ? nil : false
    end
  end
end
