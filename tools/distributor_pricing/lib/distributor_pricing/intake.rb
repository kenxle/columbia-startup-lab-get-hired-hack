# frozen_string_literal: true

require "digest"
require "bigdecimal"
require_relative "catalog"

module DistributorPricing
  class Intake
    UNIT_MAP = { "ea" => "each", "pcs" => "each", "pc" => "each", "piece" => "each", "pieces" => "each",
                 "lbs" => "lb", "pound" => "lb", "pounds" => "lb", "bags" => "bag", "feet" => "ft" }.freeze
    UNIT_PATTERN = "each|ea|pcs|pc|pieces?|lbs?|pounds?|kg|bags?|ft|feet|m"
    CONTEXT_LINE = /\A(?:ship\s+to|destination|deliver(?:y)?\s+(?:to|by|date)|country|postal\s+code|rfq\s*(?:#|number)|subject|buyer|contact|phone|email)\s*:/i

    def initialize(catalog: Catalog.new)
      @catalog = catalog
    end

    def parse(rfq:, type: "email", filename: nil, destination: nil, model_lines: [])
      raise ArgumentError, "RFQ exceeds the 2 MB intake limit" if rfq.to_s.bytesize > 2_000_000
      extraction = RfqProcessing::Extractor.extract(rfq, type: type, filename: filename)
      destination ||= destination_in(rfq.to_s)
      input_lines = extraction.lines.flat_map do |line|
        segments = line.text.split(/;\s*/)
        if segments.size > 1 && segments.all? { |segment| @catalog.match(segment, {})["status"] == "exact" }
          segments.each_with_index.map { |segment, index| RfqProcessing::Extractor::Line.new(text: segment, location: "#{line.location} segment #{index + 1}") }
        else
          [line]
        end
      end
      global_cert_text = extraction.lines.select { |line| line.text.match?(/\A(?:all (?:items|lines)|every (?:item|line)|requirements|certifications)\b/i) }.map(&:text).join(" ")
      rows = input_lines.reject { |line| line.text.match?(CONTEXT_LINE) }.filter_map do |line|
        reading = RfqProcessing::RulesParser.parse(line.text, location: line.location)
        match = @catalog.match(line.text, reading.fields)
        recognized = match["status"] != "no_match"
        model_item = Array(model_lines).any? { |candidate| candidate["original_text"] == line.text }
        quantity_request = line.text.match?(/\b(?:qty|quantity)\s*[:=]?\s*\d|\b\d+\s*(?:each|ea|pcs|pieces|lbs?|kg)\b/i)
        next unless recognized || model_item || quantity_request || reading.fields["form"] || reading.fields["part_number"] || line.text.match?(/\b(?:shot|grit|ingot|sow|sheet|plate|tube|bolt|screw|washer|nut)\b/i)

        item = match["best"] && (@catalog.find(match["best"]["part_number"]) || @catalog.items.find { |i| i["item_id"] == match["best"]["item_id"] })
        quantity, unit, quantity_evidence = quantity_in(line.text, reading, item)
        model = Array(model_lines).find { |candidate| candidate["original_text"] == line.text }
        if (!quantity || !unit) && verified_model_quantity?(model, line.text, item)
          quantity, unit = model["quantity"], model["unit"]
          quantity_evidence = { "text" => model["quantity_evidence"], "explanation" => "Model extraction checked against exact RFQ quantity words; model did not price the item" }
        end
        explicit_part = item && line.text.match?(/(?<![A-Z0-9-])#{Regexp.escape(item["part_number"])}(?![A-Z0-9-])/i)
        unknowns = reading.unknowns.map { |u| u["field"] }
        # Full hardware part numbers determine form/dimensions. Supplier
        # specification holds remain in item metadata and sourcing checks.
        unknowns -= %w[part_number form material grade thickness_in width_in length_in] if explicit_part
        unknowns -= %w[form material grade] if item && item["source_catalog"] == "rudco"
        unknowns -= %w[quantity quantity_unit] if quantity && unit
        unknowns << "quantity" unless quantity
        unknowns << "quantity_unit" unless unit
        conflicts = reading.conflicts.dup
        if item
          %w[material grade thread diameter_in nominal_length_in grip_length_in thickness_in width_in length_in].each do |field|
            requested = reading.fields[field]
            supplied = item[field]
            next if requested.nil? || supplied.nil? || supplied.to_s.match?(/unconfirmed|unverified|unknown/i) || supplied == "steel"
            equal = requested.to_s.casecmp?(supplied.to_s)
            if requested.is_a?(Numeric) || supplied.is_a?(Numeric)
              equal = BigDecimal(requested.to_s) == BigDecimal(supplied.to_s) rescue false
            end
            conflicts << { "message" => "The stated #{field.tr('_', ' ')} conflicts with #{item['part_number']}; confirm the required specification." } unless equal
          end
        end
        {
          "line_id" => "line-#{rows_position(line.location)}-#{Digest::SHA256.hexdigest(line.text)[0, 8]}",
          "original_text" => line.text, "location" => line.location, "reading" => reading.fields,
          "evidence" => reading.evidence.merge("quantity" => quantity_evidence),
          "quantity" => quantity, "unit" => unit, "match" => match, "item" => item,
          "unknowns" => unknowns.uniq, "conflicts" => conflicts,
          "requested_certifications" => certificates_in([line.text, global_cert_text].join(" ")),
          "specification_assumptions" => reading.assumptions
        }
      end
      raise ArgumentError, "RFQ exceeds 100 line items" if rows.length > 100
      { "destination" => destination, "lines" => rows, "warnings" => extraction.warnings,
        "source_type" => extraction.source_type, "filename" => filename }
    end

    private

    def verified_model_quantity?(model, text, item)
      return false unless model.is_a?(Hash) && model["quantity"].is_a?(String) && model["quantity"].match?(/\A\d+(?:\.\d+)?\z/)
      evidence = model["quantity_evidence"]
      return false unless evidence.is_a?(String) && text.include?(evidence)
      quantity = BigDecimal(model["quantity"])
      return false unless quantity.positive?
      stated = evidence.match(/(?:\b(?:qty|quantity)\s*[:=]?\s*)?(\d+(?:\.\d+)?)\s*(#{UNIT_PATTERN}|bolts?|screws?|nuts?|washers?)(?:\b|$)/i)
      return false unless stated && BigDecimal(stated[1]) == quantity
      source_unit = UNIT_MAP.fetch(stated[2].downcase, stated[2].downcase)
      source_unit = "each" if item && item["purchase_unit"] == "each" && source_unit.match?(/\A(?:bolt|screw|nut|washer)s?\z/)
      source_unit == model["unit"]
    rescue ArgumentError
      false
    end

    def destination_in(text)
      match = text.match(/(?:destination|ship\s+to)\s*:\s*([A-Z]{2})\s+([A-Z0-9][A-Z0-9 -]{1,10})\s*$/i)
      match && { "country" => match[1].upcase, "postal_code" => match[2].strip }
    end

    def quantity_in(text, reading, item)
      explicit = text.match(/\b(?:qty|quantity)\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(#{UNIT_PATTERN})?\b/i)
      explicit ||= text.match(/\A\s*(\d+(?:\.\d+)?)\s*(#{UNIT_PATTERN})\b/i)
      explicit ||= text.match(/(?:^|\s)(\d+(?:\.\d+)?)\s*(each|ea|pcs|pc|pieces?|lbs?|pounds?|kg|bags?)\s*(?:[,;]|$)/i)
      if explicit
        unit = explicit[2]&.downcase
        unit = UNIT_MAP.fetch(unit, unit)
        unit ||= "each" if item && item["purchase_unit"] == "each"
        return [explicit[1], unit, { "text" => explicit[0].strip, "explanation" => "Explicit requested quantity and unit; count unit may be stated by catalog" }]
      end
      [reading.fields["quantity"]&.to_s, reading.fields["quantity_unit"], reading.evidence["quantity"]]
    end

    def certificates_in(text)
      out = []
      out << "COFC" if text.match?(/\bc\s*(?:of|o|\/)?\s*c\b|\bcofc\b|certificate of conform/i)
      out << "MTR" if text.match?(/\bmtr\b|mill (?:test|material) report/i)
      out << "COA" if text.match?(/\bcoa\b|certificate of analysis/i)
      out << "DFARS" if text.match?(/\bdfars\b/i)
      out << "REACH" if text.match?(/\breach\b/i)
      out << "RoHS" if text.match?(/\brohs\b/i)
      out
    end

    def rows_position(location)
      location.to_s.scan(/\d+/).last || "1"
    end
  end
end
