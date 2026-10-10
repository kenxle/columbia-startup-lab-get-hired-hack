class ProcessingRunsController < ApplicationController
  include QuoteWorkspace::SessionScope

  def create
    quote = workspace_quotes.find(params[:quote_id])
    # This first UI supports initial extraction and retries of empty RFQs.
    # Replacing reviewed lines needs a separate, explicit merge workflow.
    run = quote.with_lock do
      next if quote.quote_lines.exists?

      QuoteWorkspace::ProcessRfq.enqueue(quote: quote, expected_revision: params[:reviewed_version])
    end
    unless run
      redirect_to quote_path(quote), alert: "This RFQ already has quote lines. Full reprocessing is not available here, so existing lines and rep edits are preserved."
      return
    end

    case run.status
    when "queued", "running"
      redirect_to quote_path(quote), notice: "RFQ processing is #{run.status}. Refresh the quote to see the result."
    when "succeeded"
      redirect_to quote_path(quote), notice: "RFQ processing completed. Review the extracted lines."
    else
      redirect_to quote_path(quote), alert: run.error_message.presence || "RFQ processing could not start. Review the source and try again."
    end
  rescue Quote::StaleReview, QuoteWorkspace::ProcessRfq::InputError => error
    redirect_to quote_path(quote), alert: error.message
  end
end
