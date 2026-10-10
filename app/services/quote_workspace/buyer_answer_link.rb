module QuoteWorkspace
  class BuyerAnswerLink
    class Invalid < StandardError; end
    PURPOSE = "buyer-answer".freeze
    TTL = 24.hours

    def self.from_message(message, quote:)
      return [] unless message.html_part

      Nokogiri::HTML.fragment(message.html_part.decoded).css("a[href]").filter_map do |anchor|
        uri = URI.parse(anchor["href"])
        next unless uri.path == "/buyer-answer"
        token = URI.decode_www_form(uri.query.to_s).to_h["token"]
        record = BuyerAnswerToken.find_signed(token, purpose: PURPOSE) if token
        next unless record && record.quote_id == quote.id

        {label: "Line #{record.quote_line.position}: #{record.choice.fetch('label')}",
          url: Rails.application.routes.url_helpers.buyer_answer_link_path(token: token)}
      rescue URI::InvalidURIError, ArgumentError, ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end
    end

    # Keep the complete URLs in the downloadable text email, but avoid a wall
    # of signed tokens beside the same verified clickable choices on screen.
    def self.display_body(body, links:)
      tokens = links.map { |link| URI.decode_www_form(URI.parse(link.fetch(:url)).query.to_s).to_h["token"] }.compact
      body.gsub(%r{https?://[^\s<>]+}) do |url|
        uri = URI.parse(url)
        token = URI.decode_www_form(uri.query.to_s).to_h["token"]
        uri.path == "/buyer-answer" && tokens.include?(token) ? "Use the answer link below." : url
      rescue URI::InvalidURIError, ArgumentError
        url
      end
    end

    def self.for_line(line)
      return [] unless Rails.env.development? || Rails.env.test?

      line.quote.with_lock do
        line.reload
        quote = line.quote
        return [] if line.quotable? || quote.processing_revision&.dig("id").blank?

        Array(line.processing&.dig("question_choices")).filter_map do |choice|
          next unless choice.is_a?(Hash) && choice["id"].is_a?(String) && choice["id"].present? && choice["label"].is_a?(String)

          record = BuyerAnswerToken.create!(quote: quote, quote_line: line, review_revision: quote.review_revision,
            processing_revision: quote.processing_revision.fetch("id"), question_fingerprint: fingerprint(line, quote),
            choice: choice.deep_dup)
          options = {host: "127.0.0.1", port: 3100, protocol: "http"}.merge(
            Rails.application.config.action_mailer.default_url_options || {})
          {label: choice["label"], url: Rails.application.routes.url_helpers.buyer_answer_link_url(
            **options, token: record.signed_id(purpose: PURPOSE, expires_in: TTL))}
        end
      end
    end

    def self.consume!(token)
      raise Invalid unless Rails.env.development? || Rails.env.test?
      raise Invalid unless token.is_a?(String) && token.bytesize <= 4000

      record = BuyerAnswerToken.find_signed(token, purpose: PURPOSE)
      raise Invalid unless record && record.used_at.nil?

      quote = record.quote
      arguments = quote.with_lock do
        record.reload
        line = record.quote_line.reload
        choices = Array(line.processing&.dig("question_choices"))
        unless record.used_at.nil? && fingerprint(line, quote) == record.question_fingerprint && choices.include?(record.choice)
          raise Invalid
        end
        # An answer on another line may advance the quote revision. Validate this
        # line's full saved content, then let ApplyBuyerAnswer guard current races.
        {quote: quote, quote_line_id: line.id, reviewed_version: quote.review_revision,
          revision_id: quote.processing_revision&.fetch("id"), choice_id: record.choice.fetch("id")}
      end
      ApplyBuyerAnswer.call(**arguments) do
        # The answer service yields inside its final quote transaction, after its
        # revision recheck. Losing clicks cannot commit an answer or consume a token.
        changed = BuyerAnswerToken.where(id: record.id, used_at: nil).update_all(used_at: Time.current)
        raise Invalid unless changed == 1
      end
      true
    rescue ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature,
           ApplyBuyerAnswer::Invalid, Quote::StaleReview
      raise Invalid
    end

    def self.fingerprint(line, quote)
      canonical = lambda do |value|
        case value
        when Hash then value.stringify_keys.sort.to_h.transform_values { |entry| canonical.call(entry) }
        when Array then value.map { |entry| canonical.call(entry) }
        else value
        end
      end
      payload = {
        line: line.attributes.as_json.merge("updated_at" => line.updated_at&.iso8601(6)),
        source_text: Digest::SHA256.hexdigest(quote.source_text.to_s),
        source_bytes: Digest::SHA256.hexdigest(quote.source_bytes.to_s)
      }
      Digest::SHA256.hexdigest(JSON.generate(canonical.call(payload)))
    end
    private_class_method :fingerprint
  end
end
