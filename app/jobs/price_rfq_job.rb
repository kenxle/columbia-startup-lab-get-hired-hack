class PriceRfqJob < ActiveJob::Base
  queue_as :default

  def perform(run_id)
    DistributorPricing::Run.perform(run_id)
  end
end
