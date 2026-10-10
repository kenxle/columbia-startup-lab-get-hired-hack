class BuyerQuestionsController < ApplicationController
  include QuoteWorkspace::SessionScope

  before_action :set_draft
  rescue_from QuoteWorkspace::EmailPreview::Incomplete, Quote::StaleReview, with: :review_required
  rescue_from QuoteWorkspace::EmailPreview::Unavailable, with: :preview_unavailable

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

  def preview_email
    message = QuoteWorkspace::EmailPreview.call(quote: @quote, kind: "questions", expected_revision: params[:reviewed_version])
    preview_id = message["X-Local-Preview-ID"]&.value
    redirect_to(preview_id ? quote_local_preview_path(@quote, preview_id) : quote_buyer_questions_path(@quote),
      notice: "Local question email preview saved. Nothing was sent to the buyer.")
  end

  private

  def set_draft
    response.headers["Cache-Control"] = "no-store"
    @quote = workspace_quotes.find(params[:quote_id])
    @draft = QuoteWorkspace::BuyerQuestionDraft.new(@quote)
  end

  def review_required
    redirect_to quote_buyer_questions_path(@quote), alert: "Review the latest questions before opening an email preview. Every held line needs a question."
  end

  def preview_unavailable
    redirect_to quote_buyer_questions_path(@quote), alert: "Local email previews are available only in development. No email was sent."
  end
end
