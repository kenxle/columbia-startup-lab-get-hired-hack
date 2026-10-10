class LocalPreviewsController < ApplicationController
  include QuoteWorkspace::SessionScope
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  before_action :set_quote

  def index
    @previews = Dir.glob(Rails.root.join("tmp/letter_opener/*/message.eml")).filter_map do |path|
      id = File.basename(File.dirname(path))
      message = read_preview(id)
      { id: id, subject: message.subject, received_at: File.mtime(path) } if message
    end.sort_by { |entry| entry[:received_at] }.reverse
  end

  def show
    @message = read_preview(params[:id]) || raise(ActiveRecord::RecordNotFound)
    @body = (@message.text_part || @message).decoded
  end

  def download
    message = read_preview(params[:id]) || raise(ActiveRecord::RecordNotFound)
    send_data message.encoded, filename: "#{@quote.reference}-local-preview.eml", type: "message/rfc822", disposition: "attachment"
  end

  def attachment
    message = read_preview(params[:id]) || raise(ActiveRecord::RecordNotFound)
    index = params[:index].to_s
    raise ActiveRecord::RecordNotFound unless index.match?(/\A\d+\z/)
    part = message.attachments[index.to_i] || raise(ActiveRecord::RecordNotFound)
    filename = File.basename(part.filename.to_s.tr("\\", "/")).gsub(/[\r\n]/, "")
    send_data part.decoded, filename: filename.presence || "attachment", type: "application/octet-stream", disposition: "attachment"
  end

  private

  def set_quote
    raise ActiveRecord::RecordNotFound unless Rails.env.development? || Rails.env.test?
    @quote = workspace_quotes.find(params[:quote_id])
    response.headers["Cache-Control"] = "no-store"
  end

  def read_preview(id)
    return unless id.to_s.match?(UUID)
    path = Rails.root.join("tmp/letter_opener", id, "message.eml")
    return unless path.file? && path.realpath == path.expand_path && path.size <= 30.megabytes
    message = Mail.read(path.to_s)
    return unless message["X-Quote-Desk-Quote-Id"]&.value == @quote.id.to_s
    message
  rescue StandardError
    nil
  end
end
