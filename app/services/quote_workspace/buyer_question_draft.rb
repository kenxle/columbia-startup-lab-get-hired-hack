module QuoteWorkspace
  # A local draft of existing questions. This does not generate choices or send mail.
  class BuyerQuestionDraft
    class Incomplete < StandardError; end


    attr_reader :quote

    def initialize(quote)
      @quote = quote
    end

    def held_lines
      @held_lines ||= quote.quote_lines.to_a.reject(&:quotable?)
    end

    def missing_question_lines
      held_lines.select { |line| line.clarification_question.blank? }
    end

    def ready?
      held_lines.any? && missing_question_lines.empty?
    end

    def subject
      "Questions about #{quote.reference}"
    end

    def body
      raise Incomplete, "Every held line needs a question before downloading." unless ready?

      parts = [ "Draft, not sent" ]
      parts << "Subject: #{subject}"
      parts << "Buyer: #{quote.buyer_name}" if quote.buyer_name.present?
      parts << "Please clarify the following lines from your RFQ:"
      held_lines.each do |line|
        parts << "Line #{line.position}\n#{line.clarification_question}"
      end
      parts.join("\n\n") + "\n"
    end

    def filename
      "#{quote.reference}-buyer-questions.txt"
    end
  end
end
