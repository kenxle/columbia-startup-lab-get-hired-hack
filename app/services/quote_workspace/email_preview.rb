module QuoteWorkspace
  # Creates local mail artifacts only. No buyer address or SMTP transport is used.
  class EmailPreview
    class Incomplete < StandardError; end
    class Unavailable < StandardError; end

    def self.delivery_method!
      required = if Rails.env.development?
        :silent_letter_opener
      elsif Rails.env.test?
        :test
      end
      unless required && QuoteMailer.delivery_method == required &&
          QuoteMailer.delivery_methods.key?(required) && QuoteMailer.perform_deliveries
        raise Unavailable, "Local email preview is available only with silent local delivery in development or test delivery in tests."
      end
      required
    end

    def self.call(quote:, kind:, expected_revision:)
      new(quote: quote, kind: kind, expected_revision: expected_revision).call
    end

    def initialize(quote:, kind:, expected_revision:)
      @quote = quote
      @kind = kind
      @expected_revision = expected_revision
    end

    def call
      self.class.delivery_method!
      raise Incomplete, "Choose a quote or questions preview." unless %w[quote questions].include?(@kind)

      snapshot = @quote.with_lock do
        @quote.quote_lines.reload
        if @expected_revision.blank? || @expected_revision != @quote.review_revision
          raise Quote::StaleReview, "This quote changed. Review the current version before opening an email preview."
        end
        @kind == "quote" ? quote_snapshot : questions_snapshot
      end
      QuoteMailer.local_preview(snapshot: snapshot).deliver_now
    rescue FinalQuote::NotApproved, BuyerQuestionDraft::Incomplete => error
      raise Incomplete, error.message
    end

    private

    def quote_snapshot
      final = FinalQuote.new(@quote)
      pdf = PdfExport.new(@quote)
      csv = CsvExport.new(@quote)
      freeze_snapshot(
        subject: "Local preview: #{final.subject}",
        body: final.body(attachments_included: true),
        attachments: [
          {filename: pdf.filename, content_type: "application/pdf", content: pdf.to_pdf},
          {filename: csv.filename, content_type: "text/csv", content: csv.to_csv}
        ]
      )
    end

    def questions_snapshot
      draft = BuyerQuestionDraft.new(@quote)
      raise BuyerQuestionDraft::Incomplete, "Every held line needs a question before downloading." unless draft.ready?
      links = draft.held_lines.flat_map do |line|
        BuyerAnswerLink.for_line(line).map { |answer| answer.merge(label: "Line #{line.position}: #{answer[:label]}") }
      end
      freeze_snapshot(subject: "Local preview: #{draft.subject}", body: draft.body(answer_links: links), attachments: [], answer_links: links)
    end

    def freeze_snapshot(subject:, body:, attachments:, answer_links: [])
      {
        quote_id: @quote.id,
        subject: subject.gsub(/[\r\n]+/, " ").freeze,
        answer_links: answer_links.map { |answer| answer.transform_values { |value| value.dup.freeze }.freeze }.freeze,
        body: ("Local preview: Placeholder recipient buyer@example.invalid. No email is sent to the buyer.\n\n" + body).freeze,
        attachments: attachments.map { |entry| entry.transform_values { |value| value.dup.freeze }.freeze }.freeze
      }.freeze
    end
  end
end
