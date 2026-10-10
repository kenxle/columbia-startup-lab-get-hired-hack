module QuoteWorkspace
  # Explicit rep action only. The quote lock binds both attachments and the
  # local receipt to one approved revision and serializes duplicate clicks.
  class SendApprovedQuote
    class Failed < StandardError; end
    RECIPIENT = "buyer@example.invalid".freeze

    def self.call(quote:, expected_revision:)
      EmailPreview.delivery_method!
      unless QuoteMailer.raise_delivery_errors
        raise EmailPreview::Unavailable, "Local sending requires delivery errors to be reported."
      end

      quote.with_lock do
        quote.quote_lines.reload
        if expected_revision.blank? || expected_revision != quote.review_revision
          raise Quote::StaleReview, "This quote changed. Review the current approved revision before sending."
        end
        FinalQuote.new(quote).with_snapshot do
          next quote.sent_preview_id if quote.sent? && quote.sent_channel == "local_preview"

          message = EmailPreview.call(quote: quote, kind: "quote", expected_revision: expected_revision)
          preview_id = message["X-Local-Preview-ID"]&.value
          if Rails.env.development? && preview_id.blank?
            raise Failed, "The local preview could not be confirmed. The quote was not marked sent."
          end
          # Sending does not change the reviewed content or approval revision.
          quote.update_columns(sent_at: Time.current, sent_review_revision: expected_revision,
            sent_recipient: RECIPIENT, sent_channel: "local_preview", sent_preview_id: preview_id)
          preview_id
        end
      end
    rescue Quote::StaleReview, FinalQuote::NotApproved, EmailPreview::Incomplete,
           EmailPreview::Unavailable, PdfExport::UnsupportedGlyph, Failed
      raise
    rescue StandardError
      raise Failed, "The local email could not be saved. The quote was not marked sent. Try again."
    end
  end
end
