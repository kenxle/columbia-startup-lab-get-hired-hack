class BuyerTermsController < ApplicationController
  include QuoteWorkspace::SessionScope

  def create
    quote = workspace_quotes.find(params[:quote_id])
    line = quote.quote_lines.find(params[:quote_line_id])
    record = QuoteWorkspace::TeachBuyerTerm.call(
      quote: quote,
      quote_line_id: line.id,
      expected_revision: params[:reviewed_version],
      term: params[:term], field: params[:field], value: params[:value]
    )
    redirect_to quote_path(quote, line: line.id, anchor: "line-detail"),
      notice: "Saved #{record.term.inspect} for #{quote.buyer_name}, taught on #{quote.reference}. It can be used on this buyer's next RFQ."
  rescue Quote::StaleReview, QuoteWorkspace::TeachBuyerTerm::Invalid, ActiveRecord::RecordInvalid => error
    redirect_to quote_path(quote, line: line&.id, anchor: "line-detail"), alert: error.message
  end
end
