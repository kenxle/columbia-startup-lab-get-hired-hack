# Pricing expiry also guards existing approval and buyer export paths.
# Re-attach on development reload without changing the quote lane's classes.
Rails.application.config.to_prepare do
  QuoteLine.prepend(DistributorPricing::QuoteLineValidity) unless QuoteLine.ancestors.include?(DistributorPricing::QuoteLineValidity)
  Quote.prepend(DistributorPricing::QuoteValidity) unless Quote.ancestors.include?(DistributorPricing::QuoteValidity)
end
