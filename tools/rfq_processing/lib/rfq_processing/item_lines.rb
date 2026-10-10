# frozen_string_literal: true

module RfqProcessing
  # PDF schedules carry stronger item boundaries than numbered legal paragraphs.
  # Prefer an explicit unit/quantity table; retain source words, including empty
  # price cells, without manufacturing a price or a demand from packaging.
  module ItemLines
    UNIT = /(?:kg|kilograms?|lbs?|pounds?|ea|each|pcs?|pieces?|sheets?|plates?|bars?|bags?|boxes|tons?|tonnes?|metres?|meters?|m|ft)/i
    NUMBER = /\d+(?:[ ,]\d{3})*(?:\.\d+)?/
    PRODUCT = /\b(?:steel|stainless|alum(?:inium|inum)?|galv(?:anized)?|sheet|plate|bar|tube|pipe|angle|channel|bolt|shot|grit|ingot|garnet|beads?|AN\d+)\b/i
    BOILERPLATE = /\b(?:bidder|respondent|quotation no|request for quotation|closing date|tender|tax|vat|rand value|estimated value|total price|total inclusive|discount|signature|purchase order|delivery lead.time|terms and conditions)\b/i
    TABLE_END = /\b(?:total|subtotal|vat|discount|signature|delivery lead.time|respondents?|terms|section)\b/i
    HEADER = /\b(?:unit|uom)\b.*\b(?:quantity|qty)\b|\b(?:quantity|qty)\b.*\b(?:unit|uom)\b/i
    DEMAND = /\b#{UNIT}\s+#{NUMBER}\b|\b#{NUMBER}\s*#{UNIT}\b/i

    def self.pdf(extraction)
      table_rows = []
      in_table = false
      number_column = false
      current = []
      page = nil
      extraction.lines.each do |line|
        line_page = line.location[/\Apage \d+/]
        if line_page != page
          unless current.empty?
            extraction.warnings << "an item table reaches the end of #{page}; review the next page for continuation"
            table_rows << assemble(current)
          end
          current = []
          in_table = false
          page = line_page
        end
        if HEADER.match?(line.text)
          table_rows << assemble(current) unless current.empty?
          current = []
          in_table = true
          number_column = line.text.match?(/\Aline\b/i)
          next
        end
        next unless in_table

        if TABLE_END.match?(line.text)
          table_rows << assemble(current) unless current.empty?
          current = []
          in_table = false
        elsif table_row?(line)
          table_rows << assemble(current) unless current.empty?
          current = [number_column ? without_line_number(line) : line]
          unless demand_cells?((line.layout_text || line.text).strip.split(/\s{2,}/))
            extraction.warnings << "#{line.location} has no recognized demand quantity; review this incomplete item"
          end
        elsif !current.empty?
          # Wrapped description cells stay within the description column. Reject
          # left-margin paragraphs and standalone monetary/form fields.
          raw = line.layout_text || line.text
          previous = current.first.layout_text || current.first.text
          if raw.index(/\S/).to_i > previous.index(/\S/).to_i && !BOILERPLATE.match?(line.text)
            current << line
          else
            table_rows << assemble(current)
            current = []
            in_table = false
          end
        end
      end
      table_rows << assemble(current) unless current.empty?
      return table_rows unless table_rows.empty?

      extraction.warnings << "no quantity table was recognized in the PDF; review the source for omitted or wrapped items"
      # Untabulated PDFs need both a physical product and a measurable demand,
      # dimension, or part designation. Page numbers and financial thresholds do
      # not become quote lines merely because they contain digits.
      extraction.lines.select do |line|
        text = line.text
        PRODUCT.match?(text) && !BOILERPLATE.match?(text) &&
          !text.match?(/\b(?:container|pack(?:age|aging)?|per box)\b/i) &&
          (DEMAND.match?(text) || text.match?(/\d\s*(?:x|×|ga\b|gauge|mm\b|in\b|"|')|\bAN\d+/i))
      end
    end

    # Carry explicit body requirements into compliance, not the entire tender's
    # legal boilerplate or the notes belonging to another schedule row.
    def self.body_text(extraction)
      # Reuse the same boundaries that assembled wrapped descriptions. A note
      # inside an item's evidence span belongs to that item, never every row.
      # Selection here must not duplicate warnings already produced by pdf.
      selection = extraction.dup
      selection.warnings = []
      item_spans = pdf(selection).filter_map do |item|
        match = /\Apage (\d+), lines? (\d+)(?:-(\d+))?\z/.match(item.location)
        [match[1], (match[2].to_i..(match[3] || match[2]).to_i)] if match
      end
      extraction.lines.filter_map do |line|
        location = /\Apage (\d+), line (\d+)\z/.match(line.location)
        next if location && item_spans.any? { |page, span| page == location[1] && span.cover?(location[2].to_i) }

        text = line.text
        next if DEMAND.match?(text) || BOILERPLATE.match?(text)
        next unless text.match?(/\b(?:MTRs?|COA|DFARS|REACH|RoHS|mill test report|certificate of analysis)\b/i)
        next unless text.match?(/\b(?:required|require|all|each|must|compliant)\b/i)

        text
      end.join("\n")
    end

    def self.table_row?(line)
      raw = line.layout_text || line.text
      # At least two horizontal cells: a description and a quantity/unit. The
      # table header supplies context, so unknown product names remain visible.
      return false if BOILERPLATE.match?(raw)

      cells = raw.strip.split(/\s{2,}/)
      return false if cells.length < 2

      # A numbered row remains an item when its quantity is blank. Otherwise
      # a typed unit column can establish a product row with a missing demand.
      demand_cells?(cells) || cells.first.match?(/\A\d+\z/) ||
        (PRODUCT.match?(cells.first) && cells.drop(1).any? { |cell| cell.match?(/\A#{UNIT}\z/i) })
    end

    def self.demand_cells?(cells)
      # A demand must occupy table cells, not just occur inside a description
      # such as "CONTAINER SIZE: 1000 KG PER BOX".
      cells.each_with_index.any? do |cell, index|
        next false if index.zero?

        cell.match?(/\A(?:#{DEMAND})\z/) ||
          (cell.match?(/\A#{UNIT}\z/i) && [cells[index - 1], cells[index + 1]].compact.any? { |value| value.match?(/\A#{NUMBER}\z/) })
      end
    end

    def self.without_line_number(line)
      # Only a table explicitly headed "Line" establishes this as a row number.
      # Keep product identifiers in tables headed "Item" intact.
      Extractor::Line.new(text: line.text.sub(/\A\d+\s{2,}/, ""), location: line.location, layout_text: line.layout_text)
    end

    def self.assemble(lines)
      first = lines.first
      last = lines.last
      location = first.location
      if lines.length > 1 && first.location.match?(/, line \d+\z/) && last.location.match?(/, line \d+\z/)
        location = first.location.sub(/, line (\d+)\z/, ", lines \\1-#{last.location[/\d+\z/]}")
      end
      Extractor::Line.new(text: lines.map(&:text).join(" "), location: location)
    end
  end
end
