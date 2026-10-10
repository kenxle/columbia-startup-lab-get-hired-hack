class PrismTraceJob < ActiveJob::Base
  queue_as :default

  def perform(event)
    QuoteWorkspace::PrismTrace.call(event)
  end
end
