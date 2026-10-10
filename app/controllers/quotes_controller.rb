class QuotesController < ApplicationController
  include QuoteWorkspace::SessionScope

  # The intake form may name its file field any of these. The first uploaded
  # file found is stored; nothing is parsed here.
  UPLOAD_PARAMETER_KEYS = %i[source_file file upload source_upload source_bytes].freeze
  UPLOAD_TOO_LARGE_MESSAGE = "The attached file is larger than 10 MB.".freeze
  UPLOAD_TYPE_MESSAGE = "Attach a PDF, a spreadsheet (.xlsx, .xls, .csv), a text file, or an email (.eml).".freeze

  before_action :set_quote, only: %i[show approve export source]

  def index
    @quotes = workspace_quotes.includes(:quote_lines).order(created_at: :desc, id: :desc)
  end

  def new
    @quote = Quote.new
  end

  def create
    @quote = Quote.new(intake_params.merge(workspace_token: workspace_token, sample_data: false))
    upload_problem = attach_upload(@quote)

    if upload_problem.nil? && @quote.save
      begin
        run = QuoteWorkspace::ProcessRfq.enqueue(quote: @quote, expected_revision: @quote.review_revision)
        case run.status
        when "queued", "running"
          redirect_to quote_path(@quote), notice: "RFQ saved. Processing is #{run.status}. Refresh the quote to see the results."
        when "succeeded"
          redirect_to quote_path(@quote), notice: "RFQ saved and processed. Review the extracted lines."
        else
          redirect_to quote_path(@quote), alert: "RFQ saved. #{run.error_message.presence || 'Processing could not start. Review the source and retry.'}"
        end
      rescue StandardError
        # Intake is already saved. Queue failure must leave a recoverable RFQ,
        # without leaking provider, storage or adapter exception details.
        redirect_to quote_path(@quote), alert: "RFQ saved, but processing could not be queued. Open the RFQ and select Process RFQ to retry."
      end
    else
      @quote.validate
      @quote.errors.add(:base, upload_problem) if upload_problem
      render :new, status: 422
    end
  end

  def demo
    quote = QuoteWorkspace::Demo.create!(workspace_token: workspace_token)
    redirect_to quote_path(quote), notice: "Sample RFQ created. Catalog items and prices are sample data."
  end

  def show
    @return_to = params[:return_to] == "buyer_questions" ? "buyer_questions" : nil
    @lines = @quote.quote_lines.to_a
    @status = %w[all attention ready].include?(params[:status]) ? params[:status] : "all"
    @visible_lines = case @status
    when "attention" then @lines.reject(&:quotable?)
    when "ready" then @lines.select(&:quotable?)
    else @lines
    end
    @selected_line = @visible_lines.find { |line| line.id.to_s == params[:line].to_s } || @visible_lines.first
  end

  def approve
    unless params[:reviewed] == "1" && params[:reviewed_version].present?
      redirect_to quote_path(@quote), alert: "Confirm that you reviewed the lines and buyer questions before approving."
      return
    end

    if @quote.approvable?
      @quote.approve!(expected_revision: params[:reviewed_version])
      redirect_to quote_path(@quote), notice: "Quote approved. Email, PDF and CSV preparation is available."
    else
      redirect_to quote_path(@quote),
        alert: "Approval needs at least one Ready line, and every held line needs a question for the buyer."
    end
  rescue Quote::StaleReview, Quote::NotApprovable
    redirect_to quote_path(@quote), alert: "This quote changed. Review the latest lines before approving again."
  end

  def export
    unless @quote.approved?
      redirect_to quote_path(@quote), alert: "Approve the quote before exporting it."
      return
    end

    csv_export = QuoteWorkspace::CsvExport.new(@quote)
    send_data csv_export.to_csv,
      filename: csv_export.filename,
      type: "text/csv; charset=utf-8",
      disposition: "attachment"
  end

  # Always a download. Untrusted uploads are never rendered inline.
  def source
    if @quote.source_bytes.present?
      send_data @quote.source_bytes,
        filename: @quote.original_filename.presence || "#{@quote.reference}-source",
        type: "application/octet-stream",
        disposition: "attachment"
    elsif @quote.source_text.present?
      send_data @quote.source_text,
        filename: "#{@quote.reference}-source.txt",
        type: "text/plain; charset=utf-8",
        disposition: "attachment"
    else
      head :not_found
    end
  end

  private

  def set_quote
    @quote = workspace_quotes.find(params[:id])
  end

  def intake_params
    params.expect(quote: %i[title buyer_name source_text])
  end

  def uploaded_file
    quote_parameters = params[:quote]
    return nil unless quote_parameters.is_a?(ActionController::Parameters)

    UPLOAD_PARAMETER_KEYS
      .map { |key| quote_parameters[key] }
      .find { |value| value.is_a?(ActionDispatch::Http::UploadedFile) }
  end

  # Returns a problem message, or nil when the upload is absent or stored.
  # Size is checked before reading, and the read itself is bounded.
  def attach_upload(quote)
    upload = uploaded_file
    return nil if upload.nil?
    return UPLOAD_TOO_LARGE_MESSAGE if upload.size > Quote::MAXIMUM_SOURCE_BYTES

    extension = File.extname(upload.original_filename.to_s).downcase
    return UPLOAD_TYPE_MESSAGE unless Quote::ALLOWED_UPLOAD_EXTENSIONS.include?(extension)

    bytes = upload.read(Quote::MAXIMUM_SOURCE_BYTES + 1).to_s
    return UPLOAD_TOO_LARGE_MESSAGE if bytes.bytesize > Quote::MAXIMUM_SOURCE_BYTES
    return "The attached file is empty." if bytes.empty?

    quote.source_bytes = bytes.b
    quote.original_filename = Quote.sanitize_filename(upload.original_filename)
    nil
  end
end
