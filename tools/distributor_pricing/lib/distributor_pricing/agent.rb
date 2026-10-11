# frozen_string_literal: true

require "json"
require "securerandom"
require "bigdecimal"
require "time"
require_relative "engine"
require_relative "intake"
require_relative "source_book"
require_relative "market_context"
require_relative "gateway_client"
require_relative "supplier_feed"
require_relative "local_config"

module DistributorPricing
  class Agent
    VERSION = "0.1.0"

    def initialize(catalog: Catalog.new, source_book: SourceBook.new, market_context: MarketContext.new,
                   supplier_feed: nil, gateway: nil, policy: Policy.new, clock: -> { Time.now.utc })
      @catalog, @book, @markets, @feed, @gateway, @policy, @clock = catalog, source_book, market_context, supplier_feed, gateway, policy, clock
      @intake = Intake.new(catalog: catalog)
      @engine = Engine.new(policy: policy)
    end

    def self.configured(root: File.expand_path("../../../..", __dir__))
      config = LocalConfig.read(root: root)
      catalog = Catalog.new(root: root)
      gateway = GatewayClient.new(token: config["NINOO_API_KEY"], model: config["NINOO_MODEL"] || "anthropic/claude-opus-5") if config["NINOO_API_KEY"]
      feed = SupplierFeed.new(endpoint: config["DISTRIBUTOR_PROCUREMENT_FEED"]) if config["DISTRIBUTOR_PROCUREMENT_FEED"]
      new(catalog: catalog, source_book: SourceBook.new(root: root), gateway: gateway, supplier_feed: feed)
    end

    def call(rfq:, destination: nil, type: "email", filename: nil, currency: "USD", delivery_by: nil, requirements: {}, confirmed_items: nil)
      raise ArgumentError, "RFQ must be text or document bytes" unless rfq.is_a?(String)
      raise ArgumentError, "RFQ exceeds the 2 MB intake limit" if rfq.bytesize > 2_000_000
      raise ArgumentError, "Currency must be an uppercase three-letter code" unless currency.is_a?(String) && currency.match?(/\A[A-Z]{3}\z/)
      raise ArgumentError, "Requirements and specs must be objects" unless requirements.is_a?(Hash) && (!requirements.key?("specs") || requirements["specs"].is_a?(Hash))
      started = @clock.call.utc
      request_id = SecureRandom.uuid
      extraction = RfqProcessing::Extractor.extract(rfq, type: type, filename: filename)
      text = extraction.lines.map(&:text).join("\n")
      intake = @intake.parse(rfq: rfq, type: type, filename: filename, destination: destination)
      @intake.apply_confirmed_items(intake, confirmed_items, rfq: rfq)
      model_needed = intake["lines"].any? { |line| !line["quantity"] || !line["unit"] }
      interpretation = if @gateway && model_needed
        @gateway.extract(text)
      else
        { "ok" => false, "skipped" => true, "reason" => @gateway ? "Quantity and unit evidence is complete; no model call needed." : "No model configured; deterministic RFQ intake used." }
      end
      if interpretation["ok"]
        intake = @intake.parse(rfq: rfq, type: type, filename: filename, destination: destination, model_lines: interpretation["lines"])
        @intake.apply_confirmed_items(intake, confirmed_items, rfq: rfq)
      end
      original_line_count = intake["lines"].size
      intake["lines"] = consolidate(intake["lines"])
      request = {
        "request_id" => request_id, "started_at" => started.iso8601, "rfq_sha256" => Digest::SHA256.hexdigest(rfq.to_s),
        "destination" => intake["destination"], "currency" => currency, "delivery_by" => delivery_by,
        "requirements" => requirements,
        "required_competitor_count" => @policy.minimum_benchmark_suppliers,
        "items" => intake["lines"].select { |line| line["item"] && line["quantity"] && line["unit"] && line["unknowns"].empty? && line["conflicts"].empty? }.map { |line| line.slice("line_id", "quantity", "unit").merge("part_number" => line.dig("item", "part_number"), "specs" => catalog_specs(line["item"]), "requirements" => line_requirements(line, requirements)) }
      }
      # Both live material feeds and all relevant supplier pages are fetched on
      # every call. Failed lookups never reuse an earlier observation.
      material_snapshot = @markets.refresh
      source_snapshot = @book.refresh(items: intake["lines"].map { |line| line["item"] }, request: request)
      commercial = @feed ? @feed.refresh(request: request) : { "ok" => false, "error" => "No executable supplier/checkout quote feed configured.", "lines" => {} }
      commercial = validate_feed(commercial, request)
      now = @clock.call.utc
      lines = intake["lines"].map do |line|
        price_line(line, request, source_snapshot, material_snapshot, commercial, requirements, now)
      end
      enforce_order_stock!(lines)
      ready = lines.select { |line| line.dig("pricing", "status") == "ready" }
      complete = !lines.empty? && ready.size == lines.size && intake["warnings"].empty?
      subtotal = ready.sum(BigDecimal("0")) { |line| BigDecimal(line.dig("pricing", "quote_total")) }
      {
        "schema" => "distributor_pricing/v1", "agent_version" => VERSION, "request" => request,
        "calculated_at" => now.iso8601, "policy" => @policy.to_h,
        "status" => complete ? "priced_for_rep_review" : lines.empty? ? "intake_held" : "pricing_held",
        "quote" => { "currency" => currency, "price_scope" => "delivered_ex_tax", "total" => complete ? subtotal.to_s("F") : nil,
                     "valid_until" => complete ? ready.map { |line| line.dig("pricing", "quote_valid_until") }.min : nil,
                     "ready_lines_subtotal" => subtotal.to_s("F"), "ready_lines" => ready.size, "held_lines" => lines.size - ready.size,
                     "human_approval_required" => true, "automatic_send" => false, "purchased" => false },
        "lines" => lines, "original_rfq_line_count" => original_line_count, "priced_item_group_count" => lines.size, "warnings" => intake["warnings"],
        "model_interpretation" => interpretation.reject { |key, _| key == "lines" },
        "material_market_refresh" => material_snapshot,
        "commercial_feed_status" => commercial.reject { |key, _| key == "lines" }
      }
    end

    private

    # Identical requested goods share one acquisition lot and quantity tier.
    # Evidence remains attached to every original RFQ line. Requirements that
    # differ, missing quantities and conflicts are never merged.
    def consolidate(lines)
      groups = lines.group_by do |line|
        if line["item"] && line["unknowns"].empty? && line["conflicts"].empty? && line["quantity"] && line["unit"]
          [line.dig("item", "part_number"), line["unit"], line["requested_certifications"].sort,
           line["reading"].reject { |key, _| %w[quantity quantity_unit].include?(key) }]
        else
          [line["line_id"]]
        end
      end
      groups.values.map do |rows|
        first = rows.first
        next first if rows.size == 1
        ids = rows.map { |row| row["line_id"] }
        first.merge("line_id" => "group-#{Digest::SHA256.hexdigest(ids.join('|'))[0, 12]}",
                    "quantity" => rows.sum(BigDecimal("0")) { |row| BigDecimal(row["quantity"]) }.to_s("F"),
                    "original_lines" => rows.map { |row| row.slice("line_id", "original_text", "location", "quantity", "unit", "evidence") },
                    "original_text" => rows.map { |row| row["original_text"] }.join("\n"),
                    "consolidation_reason" => "Same item, unit and stated requirements; buy the combined quantity once and avoid duplicated MOQ/pack costs.")
      end
    end

    def validate_feed(feed, request)
      checked = Time.iso8601(feed.fetch("checked_at")) if feed["ok"]
      return feed if feed["ok"] && feed["request_id"] == request["request_id"] && checked >= Time.iso8601(request["started_at"]) && checked <= @clock.call.utc && feed["lines"].is_a?(Hash) && feed["lines"].values.all? { |value| value.is_a?(Hash) }
      { "ok" => false, "lines" => {}, "error" => feed["error"] || "Feed failed same-request live verification; no stored commercial quote reused." }
    rescue KeyError, ArgumentError, TypeError
      { "ok" => false, "lines" => {}, "error" => "Invalid commercial feed freshness evidence." }
    end

    def price_line(line, request, sources, markets, commercial, requirements, now)
      item = line["item"]
      questions = line["unknowns"].map { |field| "Confirm #{field.tr('_', ' ')} for this RFQ line." }
      questions += line["conflicts"].map { |conflict| conflict["message"] }
      unless item && %w[exact scored].include?(line.dig("match", "status")) && questions.empty?
        return line.reject { |key, _| key == "item" }.merge("pricing" => {
          "status" => item ? "needs_buyer" : "no_match", "unit_price" => nil, "quote_total" => nil,
          "buyer_questions" => questions.empty? ? ["Confirm the exact catalog item or source this line separately."] : questions,
          "procurement_tasks" => [], "reasons" => questions
        }, "lead_time_estimate" => LeadTime.for_line(pricing: {}, source: {}, quantity: line["quantity"]))
      end
      source = sources.fetch(item.fetch("part_number"), { "offers" => [], "public_market_prices" => [], "supplier_routes" => [], "source_checks" => [] })
      feed_line = commercial["ok"] && (commercial["lines"][line["line_id"]] || commercial["lines"][item["part_number"]]) || {}
      offers = verified_records(feed_line["offers"], request, now)
      benchmarks = verified_records(feed_line["benchmarks"], request, now)
      offers = source["offers"] if offers.empty?
      offers = offers.select { |offer| offer["currency"] == request["currency"] }
      current_requirements = line_requirements(line, requirements)
      engine_item = { "part_number" => item["part_number"], "specs" => catalog_specs(item) }
      price = @engine.price_line(item: engine_item, quantity: line["quantity"], unit: line["unit"], destination: request["destination"],
                                offers: offers, benchmarks: benchmarks, requirements: current_requirements, now: now, delivery_by: request["delivery_by"])
      material = @markets.for_item(item, snapshot: markets)
      live_material = material["status"] == "available"
      if !live_material && material_price_verified?(feed_line["material_price_evidence"], item, request, now)
        material = feed_line["material_price_evidence"].merge("status" => "available", "basis" => "Live supplier material-price evidence", "is_finished_item_price" => false)
        live_material = true
      end
      if price["status"] == "ready" && !live_material
        hold!(price, "Current applicable material-market evidence is unavailable or overdue; obtain a live material source before release.")
      end
      # Public reference failures remain visible in live_source_checks. They do
      # not invalidate independent, request-revalidated commercial evidence.
      # SourceBook excludes failed listings; Engine still requires an eligible
      # acquisition offer and five qualified delivered supplier comparisons.
      price["procurement_tasks"] ||= []
      price["procurement_tasks"] << commercial["error"] unless commercial["ok"]
      price["procurement_tasks"] << "Supplier specification fields are pending; verify them against the required standard and quote." unless item.dig("specification_verification", "dimensions_verified") != false || feed_line["specifications_verified"] == true
      if price["status"] == "ready" && item.dig("specification_verification", "dimensions_verified") == false && feed_line["specifications_verified"] != true
        hold!(price, "Catalog supplier specification holds are unresolved.")
      end
      line.reject { |key, _| key == "item" }.merge(
        "lead_time_estimate" => LeadTime.for_line(pricing: price, source: source, quantity: line["quantity"]),
        "competitor_coverage" => { "required" => @policy.minimum_benchmark_suppliers,
          "comparable_delivered_suppliers" => price.dig("pricing_analysis", "independent_benchmark_suppliers") || 0,
          "public_product_price_suppliers" => source["public_market_prices"].map { |record| record["supplier"] }.uniq.size,
          "gap" => [@policy.minimum_benchmark_suppliers - (price.dig("pricing_analysis", "independent_benchmark_suppliers") || 0), 0].max },
        "catalog_item" => item.slice("item_id", "part_number", "source_catalog", "normalized_description", "material", "grade", "form"),
        "pricing" => price, "material_market" => material, "public_market_prices" => source["public_market_prices"],
        "supplier_routes" => source["supplier_routes"], "live_source_checks" => source["source_checks"],
        "procurement_request" => {
          "part_number" => item["part_number"], "quantity" => line["quantity"], "unit" => line["unit"],
          "destination" => request["destination"], "delivery_by" => request["delivery_by"], "requirements" => current_requirements,
          "request_id" => request["request_id"], "send_automatically" => false,
          "confirm" => ["exact specification and certifications", "purchase quantity, packs and MOQ", "current available/reserved stock", "destination-specific freight and all fees", "delivered lead time", "validity and payment terms", "nonrecoverable taxes or resale exemption", "return/restocking and warranty terms"]
        }
      )
    end

    def verified_records(records, request, now)
      Array(records).filter_map do |record|
        next unless record.is_a?(Hash)
        checked = Time.iso8601(record.fetch("revalidated_at"))
        next unless record["revalidated_for_request_id"] == request["request_id"] && checked >= Time.iso8601(request["started_at"]) && checked <= now
        record.merge("original_source_observed_at" => record["retrieved_at"], "retrieved_at" => checked.iso8601)
      rescue KeyError, ArgumentError, TypeError
        nil
      end
    end

    def line_requirements(line, requirements)
      specs = line["reading"].slice("material", "grade", "standard", "finish", "diameter_in", "thread", "thickness_in", "width_in", "length_in").reject { |_, value| value.nil? }
      requirements.merge("certifications" => (Array(requirements["certifications"]) + line["requested_certifications"]).uniq,
                         "specs" => (requirements["specs"] || {}).merge(specs))
    end

    def material_price_verified?(evidence, item, request, now)
      return false unless evidence.is_a?(Hash) && evidence["request_id"] == request["request_id"] && evidence["source_url"].to_s.start_with?("https://")
      return false unless evidence["material"].to_s.casecmp?(item["material"].to_s) && !evidence["material"].to_s.empty?
      return false if item["grade"] && evidence["grade"] != item["grade"]
      value = BigDecimal(evidence.fetch("value").to_s)
      checked = Time.iso8601(evidence.fetch("checked_at"))
      observed = Date.iso8601(evidence.fetch("observation_date"))
      value.finite? && value.positive? && checked >= Time.iso8601(request["started_at"]) && checked <= now && observed <= now.to_date && (now.to_date - observed).to_i <= 100 && !evidence["unit"].to_s.empty? && evidence["currency"].to_s.match?(/\A[A-Z]{3}\z/)
    rescue KeyError, ArgumentError, TypeError
      false
    end

    def catalog_specs(item)
      keys = %w[material grade thread nominal_length_in grip_length_in diameter_in thickness_in width_in length_in standard]
      item.slice(*keys).reject { |_, value| value.nil? || value == "steel" || value.to_s.match?(/unconfirmed|unverified|unknown/i) }
    end

    def hold!(price, reason)
      price["status"] = "needs_procurement"
      price["unit_price"] = price["line_total"] = price["quote_total"] = nil
      price["procurement_tasks"] = Array(price["procurement_tasks"]) | [reason]
      price["reasons"] = Array(price["reasons"]) | [reason]
    end

    def enforce_order_stock!(lines)
      groups = lines.select { |line| line.dig("pricing", "status") == "ready" }.group_by do |line|
        offer = line.dig("pricing", "procurement_plan", "supplier_offer_evidence") || {}
        [offer["supplier"], offer["supplier_sku"], offer["stock_pool_id"] || offer["source_url"]]
      end
      groups.each_value do |rows|
        total = rows.sum(BigDecimal("0")) { |row| BigDecimal(row.dig("pricing", "cost_breakdown", "purchase_quantity").to_s) }
        stocks = rows.map { |row| BigDecimal(row.dig("pricing", "procurement_plan", "supplier_offer_evidence", "stock_quantity").to_s) }
        rows.each { |row| hold!(row["pricing"], "Combined RFQ lines exceed this supplier's confirmed stock pool; consolidate or find additional supply.") } if total > stocks.min
      end
    end
  end
end
