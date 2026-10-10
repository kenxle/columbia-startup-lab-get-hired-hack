class FinalQuotesController < ApplicationController
  include QuoteWorkspace::SessionScope

  before_action :set_quote
  rescue_from QuoteWorkspace::FinalQuote::NotApproved, QuoteWorkspace::EmailPreview::Incomplete, Quote::StaleReview, with: :review_required
  rescue_from QuoteWorkspace::EmailPreview::Unavailable, with: :preview_unavailable
  rescue_from QuoteWorkspace::PdfExport::UnsupportedGlyph, with: :unsupported_pdf_text

  def show
    @draft = QuoteWorkspace::FinalQuote.new(@quote)
    @body = @draft.body
  end

  def download
    draft = QuoteWorkspace::FinalQuote.new(@quote)
    send_data draft.body, filename: draft.filename,
      type: "text/plain; charset=utf-8", disposition: "attachment"
  end

  def pdf
    export = QuoteWorkspace::PdfExport.new(@quote)
    send_data export.to_pdf, filename: export.filename,
      type: "application/pdf", disposition: "attachment"
  end

  def preview_email
    QuoteWorkspace::EmailPreview.call(quote: @quote, kind: "quote", expected_revision: params[:reviewed_version])
    redirect_to quote_final_quote_path(@quote),
      notice: "Local email preview opened with PDF and CSV attachments. Nothing was sent to the buyer."
  end

  private

  def set_quote
    response.headers["Cache-Control"] = "no-store"
    @quote = workspace_quotes.find(params[:quote_id])
  end

  def review_required
    redirect_to quote_path(@quote), alert: "Review and approve the latest quote before preparing its email or PDF."
  end

  def preview_unavailable
    redirect_to quote_final_quote_path(@quote), alert: "Local email previews are available only in development. No email was sent."
  end

  def unsupported_pdf_text
    redirect_to quote_final_quote_path(@quote), alert: "This PDF cannot display one of the quote's characters. Download the text or CSV to preserve the exact specification. No email was sent."
  end
end
