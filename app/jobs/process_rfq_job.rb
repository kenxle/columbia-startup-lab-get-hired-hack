class ProcessRfqJob < ActiveJob::Base
  queue_as :default

  def perform(run_id)
    QuoteWorkspace::ProcessRfq.perform(run_id)
  end
end
