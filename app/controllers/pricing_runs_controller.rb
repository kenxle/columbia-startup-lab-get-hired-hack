class PricingRunsController < ApplicationController
  include QuoteWorkspace::SessionScope

  def show
    @quote = workspace_quotes.find(params[:quote_id])
    @run = PricingRun.where(quote_id: @quote.id).order(id: :desc).first
    @output = @run&.output_available?(@quote) ? @run.result : nil
    @prices_current = @run&.quote_prices_current?(@quote)
    respond_to do |format|
      format.html
      format.json { render json: { status: @run&.status || "not_requested", current: @run&.current_for?(@quote) || false,
        quote_prices_current: !!@prices_current, result: @output, error: @run&.error_message } }
    end
  end

  def create
    @quote = workspace_quotes.find(params[:quote_id])
    input = params.require(:pricing).permit(:country, :postal_code, :currency, :delivery_by)
    run = DistributorPricing::Run.enqueue(quote: @quote, expected_revision: params[:reviewed_version],
      destination: { "country" => input[:country].to_s.strip.upcase, "postal_code" => input[:postal_code].to_s.strip },
      currency: input[:currency].to_s.strip.upcase, delivery_by: input[:delivery_by].presence)
    respond_to do |format|
      format.html { redirect_to quote_pricing_path(@quote), notice: "Price check #{run.status}. Review each line and its sources." }
      format.json { render json: { id: run.id, status: run.status, status_url: quote_pricing_path(@quote, format: :json) }, status: :accepted }
    end
  rescue DistributorPricing::Run::InputError, Quote::StaleReview, ActionController::ParameterMissing => error
    message = error.is_a?(ActionController::ParameterMissing) ? "Enter a destination before checking prices." : error.message
    respond_to do |format|
      format.html { redirect_to quote_pricing_path(@quote), alert: message }
      format.json { render json: { error: message }, status: :unprocessable_entity }
    end
  end
end
