class BuyerAnswerLinksController < ApplicationController
  def show
    response.set_header("Cache-Control", "no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    QuoteWorkspace::BuyerAnswerLink.consume!(params[:token])
    @accepted = true
    render :show, layout: false
  rescue QuoteWorkspace::BuyerAnswerLink::Invalid
    @accepted = false
    render :show, layout: false, status: :unprocessable_entity
  end
end
