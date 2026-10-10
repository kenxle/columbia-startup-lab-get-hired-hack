# frozen_string_literal: true

require "json"
require_relative "../../../rfq_processing/lib/rfq_processing"
# Explicit requires also work on Windows, where the processor's absolute glob
# can return no files. Keep the processor's implementation and ownership intact.
%w[units gauge_table lexicon buyer_profile rules_parser compliance extractor catalog_matcher].each do |name|
  require_relative "../../../rfq_processing/lib/rfq_processing/#{name}"
end

module DistributorPricing
  class Catalog
    attr_reader :items

    def initialize(root: File.expand_path("../../../..", __dir__))
      @root = root
      @items = %w[aviation rudco metals].flat_map do |name|
        path = File.join(root, "data", name, "catalog.json")
        next [] unless File.file?(path)

        JSON.parse(File.read(path)).map { |row| normalize(row, name) }
      end
      @by_part = @items.to_h { |row| [row.fetch("part_number").upcase, row] }
      @matcher = RfqProcessing::CatalogMatcher.new(@items)
    end

    def find(part)
      @by_part[part.to_s.strip.upcase]
    end

    def match(text, fields)
      explicit = @by_part.keys.select { |pn| text.match?(/(?<![A-Z0-9-])#{Regexp.escape(pn)}(?![A-Z0-9-])/i) }
      return { "status" => "ambiguous", "best" => nil, "candidates" => explicit.map { |pn| find(pn) } } if explicit.length > 1
      return exact(find(explicit.first)) if explicit.length == 1

      # RudCo's material names and grade must both be present. Never choose a
      # grade on its own or substitute A356 for 356.
      rudco = @items.select do |item|
        next false unless item["source_catalog"] == "rudco"
        material = item["material"].to_s
        grade = item["grade"].to_s
        material_match = text.match?(/#{Regexp.escape(material).gsub('\\ ', '\\s+')}/i)
        material_match ||= material.include?("aluminum") && text.match?(/\balumin(?:um|ium)\b/i)
        grade_match = !grade.empty? && text.match?(/(?<![A-Z0-9])#{Regexp.escape(grade).gsub('\\-', '[- ]?')}(?![A-Z0-9])/i)
        material_match && grade_match
      end
      return exact(rudco.first) if rudco.length == 1
      return { "status" => "ambiguous", "best" => nil, "candidates" => rudco.first(3) } if rudco.length > 1

      @matcher.match(line_text: text, spec: fields)
    end

    private

    def exact(item)
      { "status" => "exact", "best" => { "item_id" => item["item_id"], "part_number" => item["part_number"], "score" => 1.0 }, "candidates" => [] }
    end

    def normalize(row, name)
      part = row["part_number"] || row["pn"]
      row.merge("source_catalog" => name, "part_number" => part,
                "item_id" => row["item_id"] || part, "form" => row["shape"] || row["form"],
                "purchase_unit" => row["purchase_unit"] || row["unit"],
                "normalized_description" => row["normalized_description"] || row["description"])
    end
  end
end
