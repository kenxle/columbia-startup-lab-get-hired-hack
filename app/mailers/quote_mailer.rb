class QuoteMailer < ActionMailer::Base
  default from: "quote-desk@example.invalid"

  def local_preview(snapshot:)
    method = QuoteWorkspace::EmailPreview.delivery_method!
    headers["X-Quote-Desk-Quote-Id"] = snapshot.fetch(:quote_id).to_s
    snapshot.fetch(:attachments).each do |attachment|
      attachments[attachment.fetch(:filename)] = {
        mime_type: attachment.fetch(:content_type), content: attachment.fetch(:content)
      }
    end

    mail(to: "buyer@example.invalid", subject: snapshot.fetch(:subject).gsub(/[\r\n]+/, " "),
      delivery_method: method) do |format|
      format.text { render plain: snapshot.fetch(:body) }
    end
  end
end
