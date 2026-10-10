# The rep enters a client's description, sees the catalog items it most likely
# means, and approves one or more. Approved items are added to an RFQ and the
# client's memory learns from the choice.
class CatalogMatchesController < ApplicationController
  include QuoteWorkspace::SessionScope

  NEW_QUOTE = "new".freeze

  before_action :set_client, only: %i[index teach forget]
  before_action :set_match_request, only: %i[show approve]

  def index
    @clients = workspace_clients.order(:name)
    @recent = @client ? @client.match_requests.order(created_at: :desc).limit(10) : []
    @terms = @client ? CatalogMatch::ClientMemory.new(@client).terms.sort_by(&:term) : []
  end

  def create
    name = params[:client_name].to_s.squish
    description = params[:description].to_s.strip
    if name.blank? || description.blank?
      redirect_to catalog_matches_path(client_id: params[:client_id]),
                  alert: "Enter the client's name and what they asked for."
      return
    end

    client = workspace_clients.find_or_create_by!(name: name)
    match_request = CatalogMatch::Suggest.call(client: client, description: description.first(2_000))
    redirect_to catalog_match_path(match_request)
  rescue ActiveRecord::RecordInvalid => error
    redirect_to catalog_matches_path, alert: error.record.errors.full_messages.to_sentence
  end

  def show
    @client = @match_request.client
    @catalog = CatalogMatch::Catalog.default
    @candidates = Array(@match_request.result["candidates"])
    @closest = Array(@match_request.result["closest"])
    @quotes = workspace_quotes.order(created_at: :desc).limit(20)
  end

  def approve
    quote = target_quote
    outcome = CatalogMatch::Approve.call(
      match_request: @match_request,
      part_numbers: Array(params[:part_numbers]),
      quote: quote,
      quantity: params[:quantity].presence
    )
    learned = outcome[:learned].map(&:term)
    notice = "Added #{outcome[:lines].size} #{'line'.pluralize(outcome[:lines].size)} to #{quote.reference}."
    notice += " Remembered for #{@match_request.client.name}: #{learned.map { |term| "\"#{term}\"" }.to_sentence}." if learned.any?
    redirect_to quote_path(quote, line: outcome[:lines].first.id), notice: notice
  rescue CatalogMatch::Approve::Invalid, ActiveRecord::RecordInvalid => error
    redirect_to catalog_match_path(@match_request), alert: error.message
  end

  def teach
    CatalogMatch::ClientMemory.new(@client).teach!(
      term: params[:term], field: params[:field], value: params[:value], part_number: params[:part_number].presence
    )
    redirect_to catalog_matches_path(client_id: @client.id), notice: "#{@client.name}: \"#{params[:term].to_s.squish}\" saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to catalog_matches_path(client_id: @client.id), alert: error.record.errors.full_messages.to_sentence
  end

  def forget
    @client.client_terms.find(params[:term_id]).destroy!
    redirect_to catalog_matches_path(client_id: @client.id), notice: "Forgotten."
  end

  private

  def workspace_clients
    Client.for_workspace(workspace_token)
  end

  def set_client
    @client = workspace_clients.find_by(id: params[:client_id]) if params[:client_id].present?
    return if @client || action_name == "index"

    redirect_to catalog_matches_path, alert: "Choose a client first."
  end

  def set_match_request
    @match_request = MatchRequest.joins(:client).merge(workspace_clients).find(params[:id])
  end

  # Approving into a new RFQ creates one for the client, holding their request text.
  def target_quote
    if params[:quote_id].blank? || params[:quote_id] == NEW_QUOTE
      workspace_quotes.create!(
        title: "#{@match_request.client.name}: #{@match_request.description.truncate(60)}",
        buyer_name: @match_request.client.name,
        source_text: @match_request.description,
        sample_data: true
      )
    else
      workspace_quotes.find(params[:quote_id])
    end
  end
end
