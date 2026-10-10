module QuoteWorkspace
  # Only a deliberate rep submission writes memory. Processing results and
  # catalog candidates cannot call this by posting their own provenance.
  class TeachBuyerTerm
    class Invalid < StandardError; end
    # Ken's demo explicitly teaches gauge and thickness. This quote-scoped
    # form adds numeric validation and trusted RFQ provenance to that action.
    TEACHABLE_FIELDS = (ClientTerm::TEACHABLE_FIELDS + %w[gauge thickness]).uniq.freeze

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(quote:, quote_line_id:, expected_revision:, term:, field:, value:)
      @quote = quote
      @quote_line_id = quote_line_id
      @expected_revision = expected_revision
      @term = term
      @field = field
      @value = value
    end

    def call
      @quote.with_lock do
        unless @expected_revision.present? && @expected_revision == @quote.review_revision
          raise Quote::StaleReview, "This RFQ changed. Review the current line before teaching a buyer term."
        end
        line = @quote.quote_lines.find(@quote_line_id)
        raise Invalid, "Add a buyer name before teaching buyer-specific terms." if @quote.buyer_name.blank?
        validate_input!

        client = BuyerContext.for(@quote).fetch(:client)
        client.with_lock do
          record = client.client_terms.find_or_initialize_by(term: ClientTerm.normalize_value_for(:term, @term))
          record.assign_attributes(
            source: "taught", times_confirmed: 1,
            meaning: {
              "fields" => { @field => @value.strip },
              "confirmed_on" => @quote.reference,
              "provenance" => {
                "method" => "explicit_rep_teaching",
                "quote_id" => @quote.id,
                "quote_reference" => @quote.reference,
                "quote_line_id" => line.id,
                "taught_at" => Time.current.utc.iso8601
              }
            }
          )
          record.save!
          record
        end
      end
    end

    private

    def validate_input!
      unless @term.is_a?(String) && @term.valid_encoding? && @term.squish.present? && @term.squish.length <= 120
        raise Invalid, "Enter buyer wording of 1 to 120 characters."
      end
      unless @field.is_a?(String) && TEACHABLE_FIELDS.include?(@field)
        raise Invalid, "Choose a supported specification field. Price and quantity cannot be taught here."
      end
      unless @value.is_a?(String) && @value.valid_encoding? && @value.strip.present? && @value.strip.length <= 200
        raise Invalid, "Enter a confirmed meaning of 1 to 200 characters."
      end
      if %w[gauge thickness].include?(@field)
        begin
          number = ClientTerm.cast(@field, @value)
        rescue FloatDomainError
          number = nil
        end
        unless number.is_a?(Numeric) && number.finite? && number.positive?
          raise Invalid, "Enter a positive finite number for #{@field}. Thickness is in inches."
        end
      end
    end
  end
end
