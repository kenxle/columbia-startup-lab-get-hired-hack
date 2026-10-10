module QuoteWorkspace
  # A local demonstration artifact, never a buyer delivery or confidence gate.
  class DispatchBuyerQuestion
    def self.call(quote_line_id:, fingerprint:)
      return unless Rails.env.development? || Rails.env.test?

      line = QuoteLine.find_by(id: quote_line_id)
      return unless line

      line.quote.with_lock do
        line.reload
        return unless line.question_preview_eligible? && line.question_delivery_fingerprint == fingerprint

        existing = line.buyer_question_deliveries.find_by(fingerprint: fingerprint, channel: "local_preview")
        return existing if existing

        delivery = line.buyer_question_deliveries.create!(
          quote: line.quote, fingerprint: fingerprint, recipient: "buyer@example.invalid",
          buyer_name: line.quote.buyer_name, line_position: line.position, source_line_id: line.line_id,
          question_text: line.clarification_question, channel: "local_preview", status: "pending")
        choices = Array(line.processing&.dig("question_choices")).filter_map do |choice|
          choice["label"] if choice.is_a?(Hash) && choice["label"].is_a?(String)
        end
        options = choices.each_with_index.map { |label, index| "#{index + 1}. #{label}" }.join("\n")
        snapshot = {
          subject: "Local preview: #{line.quote.reference}, question for line #{line.position}".freeze,
          body: ("Local preview only. No email has been sent to the buyer.\n" \
            "Placeholder recipient: buyer@example.invalid\n\n" \
            "#{line.quote.reference}, line #{line.position}\n#{line.clarification_question}\n" \
            "#{options}\nThe buyer can also write their own answer.\n").freeze,
          attachments: [].freeze
        }.freeze
        begin
          EmailPreview.delivery_method!
          QuoteMailer.local_preview(snapshot: snapshot).deliver_now
          delivery.update!(status: "previewed", previewed_at: Time.current)
        rescue StandardError
          delivery.update!(status: "failed", error_message: "Local question preview could not be created.")
        end
        delivery
      end
    rescue ActiveRecord::RecordNotFound
      nil # A whole-RFQ replacement can remove the queued line before execution.
    end
  end
end
