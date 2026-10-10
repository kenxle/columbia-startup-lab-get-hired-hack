class BuyerQuestionsController < ApplicationController
  include QuoteWorkspace::SessionScope

  before_action :set_draft

  def show
  end

  def download
    unless @draft.ready?
      redirect_to quote_buyer_questions_path(@quote),
        alert: "A draft needs at least one held line and a question for every held line."
      return
    end

    send_data @draft.body,
      filename: @draft.filename,
      type: "text/plain; charset=utf-8",
      disposition: "attachment"
  end

  private

  def set_draft
    @quote = workspace_quotes.find(params[:quote_id])
    @draft = QuoteWorkspace::BuyerQuestionDraft.new(@quote)
  end
end
