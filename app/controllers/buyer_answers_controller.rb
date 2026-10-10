class BuyerAnswersController < ApplicationController
  include QuoteWorkspace::SessionScope

  def create
    quote = workspace_quotes.find(params[:quote_id])
    line = QuoteWorkspace::ApplyBuyerAnswer.call(quote: quote, quote_line_id: params[:quote_line_id],
      reviewed_version: params[:reviewed_version], revision_id: params[:revision_id],
      choice_id: params[:choice_id], free_text: params[:free_text])
    redirect_to quote_path(quote, line: line.id), notice: "Answer applied. Review the updated line and approve the quote again."
  rescue QuoteWorkspace::ApplyBuyerAnswer::Invalid, Quote::StaleReview => error
    redirect_to quote_path(quote, line: params[:quote_line_id]), alert: error.message
  end
end
