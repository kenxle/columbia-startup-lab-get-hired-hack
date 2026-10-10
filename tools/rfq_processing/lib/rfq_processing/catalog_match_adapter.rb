# frozen_string_literal: true

module RfqProcessing
  # Wraps Tisch's Rails matcher (CatalogMatch::Matcher.call(text, client:)) in the
  # matcher contract from docs/rfq_processing/RESULT-FORMAT.md, so RFQ processing
  # stays the single assembler of the hash the app receives.
  #
  #   matcher = RfqProcessing::CatalogMatchAdapter.new(client: client)
  #   RfqProcessing.process(content: text, type: "email", matcher: matcher)
  #
  # Tisch's Result: outcome "match" | "candidates" | "no_match", candidates and
  # closest as Candidate structs (item hash, checks, confidence 0 to 100), and one
  # buyer question. The contract: status exact | scored | ambiguous | no_match,
  # scores 0 to 1, best and candidates as hashes.
  class CatalogMatchAdapter
    THRESHOLD = 0.8

    def initialize(client: nil, catalog: nil, service: nil)
      @client = client
      @catalog = catalog
      @service = service
    end

    def match(line_text:, spec: {}, quantity: nil, quantity_unit: nil)
      direct = call_contract(line_text, spec, quantity, quantity_unit)
      return direct if direct

      result = call_service(line_text)
      return { "status" => "no_match", "threshold" => THRESHOLD, "best" => nil, "candidates" => [], "total_candidates" => 0, "reason" => "matcher unavailable" } unless result

      candidates = Array(result.candidates).map { |c| convert(c) }
      closest = Array(result.closest).map { |c| convert(c) }
      case result.outcome.to_s
      when "match"
        best = candidates.first
        { "status" => best && best["score"] >= 1.0 ? "exact" : "scored", "threshold" => THRESHOLD, "best" => best,
          "candidates" => candidates, "total_candidates" => candidates.size, "question" => nil }
      when "candidates"
        { "status" => "ambiguous", "threshold" => THRESHOLD, "best" => nil, "candidates" => candidates.first(3),
          "total_candidates" => candidates.size, "question" => result.question }
      else
        { "status" => "no_match", "threshold" => THRESHOLD, "best" => nil, "candidates" => closest.first(3),
          "total_candidates" => 0, "question" => result.question,
          "reason" => closest.any? ? "Closest items listed, none fits: #{closest.first['reason']}" : "No catalog item fits." }
      end
    end

    private

    # Tisch's CatalogMatch::Contract speaks this contract directly (13:30): a hash in, a hash out.
    def call_contract(text, spec, quantity, quantity_unit)
      contract = @service.nil? && defined?(::CatalogMatch::Contract) && ::CatalogMatch::Contract
      return nil unless contract

      input = { "line_text" => text, "spec" => spec.to_h.transform_keys(&:to_s), "quantity" => quantity, "quantity_unit" => quantity_unit }
      input["client"] = @client.respond_to?(:name) ? @client.name : @client if @client
      out = if @client.respond_to?(:workspace_token)
              contract.call(input, workspace_token: @client.workspace_token)
            else
              contract.call(input)
            end
      normalize(out)
    rescue StandardError => e
      warn "CatalogMatchAdapter contract: #{e.class}: #{e.message}"
      nil
    end

    PRICE_KEYS = %w[market_reference observation_ids list_price_usd_per_lb list_price_source unit purchase_unit catalog
                    stock_reported stock_scope catalog_provenance in_stock lead_time_days description normalized_description].freeze

    def normalize(out)
      out = out.to_h.transform_keys(&:to_s)
      out["candidates"] = Array(out["candidates"]).map { |c| enrich(c.to_h.transform_keys(&:to_s)) }
      out["best"] = out["best"] && enrich(out["best"].to_h.transform_keys(&:to_s))
      out["threshold"] ||= THRESHOLD
      out["total_candidates"] ||= [out["candidates"].size, out["best"] ? 1 : 0].max
      out
    end

    # The contract entry names the item; the price, unit, and stock facts live on the catalog row.
    def enrich(entry)
      return entry if entry["market_reference"] || entry["list_price_usd_per_lb"]

      row = catalog_row(entry["item_id"] || entry["part_number"])
      return entry unless row

      extra = row.slice(*PRICE_KEYS)
      entry["description"] ||= extra["description"] || extra["normalized_description"]
      entry["purchase_unit"] ||= extra["purchase_unit"] || extra["unit"]
      entry["stock"] = extra.slice("stock_reported", "stock_scope", "catalog_provenance", "in_stock")
      entry.merge(extra.slice("market_reference", "observation_ids", "list_price_usd_per_lb", "list_price_source", "catalog"))
    end

    def catalog_row(id)
      return nil if id.nil?

      items = if @catalog.respond_to?(:items) then @catalog.items
              elsif defined?(::CatalogMatch::Catalog) then ::CatalogMatch::Catalog.default.items
              end
      Array(items).map { |i| i.to_h.transform_keys(&:to_s) }.find { |i| [i["item_id"], i["pn"]].compact.include?(id.to_s) }
    rescue StandardError
      nil
    end

    def call_service(text)
      service = @service || (defined?(::CatalogMatch::Matcher) && ::CatalogMatch::Matcher)
      return nil unless service

      args = { client: @client }
      args[:catalog] = @catalog if @catalog
      service.call(text, **args)
    rescue StandardError => e
      warn "CatalogMatchAdapter: #{e.class}: #{e.message}"
      nil
    end

    def convert(candidate)
      item = (candidate.respond_to?(:item) ? candidate.item : candidate).to_h.transform_keys(&:to_s)
      checks = candidate.respond_to?(:checks) ? Array(candidate.checks) : []
      exact = checks.select { |c| c[:status] == :exact }.map { |c| c[:field].to_s }
      near = checks.select { |c| c[:status] == :near }.map { |c| "#{c[:field]}: #{c[:note] || c[:reason] || 'close, confirm'}" }
      conflicts = checks.select { |c| c[:status] == :conflict }.map { |c| "#{c[:field]}: #{c[:note] || c[:reason] || 'differs'}" }
      confidence = candidate.respond_to?(:confidence) ? candidate.confidence.to_f : 0.0
      {
        "item_id" => item["item_id"] || item["pn"] || item["sku"] || item["id"],
        "part_number" => item["pn"] || item["part_number"],
        "description" => item["description"] || item["normalized_description"],
        "score" => (confidence / 100.0).round(2),
        "matched_on" => exact,
        "mismatches" => near + conflicts,
        "reason" => reason_for(exact, near, conflicts),
        "market_reference" => item["market_reference"],
        "observation_ids" => item["observation_ids"],
        "purchase_unit" => item["purchase_unit"] || item["unit"],
        "list_price_usd_per_lb" => item["list_price_usd_per_lb"],
        "list_price_source" => item["list_price_source"],
        "catalog" => item["catalog"],
        "stock" => item.slice("stock_reported", "stock_scope", "catalog_provenance")
      }
    end

    def reason_for(exact, near, conflicts)
      parts = []
      parts << "agrees on #{exact.join(', ')}" if exact.any?
      parts << "to confirm: #{near.join('; ')}" if near.any?
      parts << "differs on #{conflicts.join('; ')}" if conflicts.any?
      parts.empty? ? "no field checks" : parts.join(". ").capitalize
    end
  end
end
