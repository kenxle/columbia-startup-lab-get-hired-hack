class DispatchBuyerQuestionJob < ActiveJob::Base
  queue_as :default

  def perform(quote_line_id, fingerprint)
    QuoteWorkspace::DispatchBuyerQuestion.call(quote_line_id: quote_line_id, fingerprint: fingerprint)
  end
end
