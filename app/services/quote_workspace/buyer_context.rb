module QuoteWorkspace
  # Loads existing buyer memory. This does not learn from an unreviewed RFQ.
  class BuyerContext
    def self.for(quote)
      new(quote).call
    end

    def initialize(quote)
      @quote = quote
      @name = Client.normalize_value_for(:name, quote.buyer_name)
    end

    def call
      return { client: nil, buyer_terms: [] } if @name.blank?

      client = find_client || create_client
      # Automatic learning is not yet safe. Only explicit rep teaching can
      # influence a later RFQ until the learning provenance contract is fixed.
      terms = client.client_terms.where(source: "taught").order(:id).map do |record|
        meaning = {}
        fields = record.field_values
        meaning["fields"] = fields.deep_dup if fields.any?
        meaning["part_number"] = record.part_number if record.part_number.present?
        entry = {
          "term" => record.term,
          "meaning" => meaning,
          "source" => record.source,
          "times_confirmed" => record.times_confirmed,
          "client_name" => client.name
        }
        provenance = provenance_for(record, client)
        if provenance
          meaning["provenance"] = provenance.deep_dup
          entry["provenance"] = provenance
          entry["source_quote_reference"] = provenance["quote_reference"]
          entry["confirmed_on"] = provenance["quote_reference"]
        end
        entry
      end
      { client: client, buyer_terms: terms }
    end

    private

    def provenance_for(record, client)
      provenance = record.meaning.is_a?(Hash) && record.meaning["provenance"]
      return unless provenance.is_a?(Hash) && provenance["method"] == "explicit_rep_teaching"
      return unless %w[quote_id quote_line_id].all? { |key| provenance[key].is_a?(Integer) && provenance[key].positive? }
      return unless provenance["taught_at"].is_a?(String) && provenance["taught_at"].length <= 40

      source_quote = Quote.for_workspace(@quote.workspace_token).find_by(id: provenance["quote_id"])
      return unless source_quote && source_quote.reference == provenance["quote_reference"]
      return unless Client.normalize_value_for(:name, source_quote.buyer_name).to_s.casecmp?(client.name)
      return unless source_quote.quote_lines.exists?(id: provenance["quote_line_id"])
      return unless record.meaning["confirmed_on"] == source_quote.reference && record.valid?
      return unless record.field_values.values.all? { |value| !value.is_a?(Numeric) || value.finite? }

      Time.iso8601(provenance["taught_at"])
      provenance.slice("method", "quote_id", "quote_reference", "quote_line_id", "taught_at").deep_dup
    rescue ArgumentError
      nil
    end

    def find_client
      # Compare in Ruby so Unicode case and legacy spacing use the same
      # normalization as new records, instead of SQLite's ASCII-only LOWER.
      Client.for_workspace(@quote.workspace_token).order(:id).detect do |client|
        Client.normalize_value_for(:name, client.name).casecmp?(@name)
      end
    end

    def create_client
      Client.create!(name: @name, workspace_token: @quote.workspace_token)
    rescue ActiveRecord::RecordInvalid => error
      details = error.record.errors.details
      duplicate_name = details.keys == [ :name ] && details[:name].present? &&
        details[:name].all? { |entry| entry[:error] == :taken }
      existing = find_client if duplicate_name
      return existing if existing

      raise
    rescue ActiveRecord::RecordNotUnique
      existing = find_client
      return existing if existing

      raise
    end
  end
end
