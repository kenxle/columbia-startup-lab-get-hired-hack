# frozen_string_literal: true

module RfqProcessing
  # Email, PDF, or spreadsheet bytes in; text lines with their positions out.
  # A page with no text is a warning the rep must see, never a silent skip.
  module Extractor
    Extraction = Struct.new(:lines, :warnings, :pages, :rows, :source_type, keyword_init: true)
    Line = Struct.new(:text, :location, keyword_init: true)

    PDF_TEXT_PATH = File.expand_path("../../../pdf_text/lib/pdf_text", __dir__)

    def self.extract(content, type:, filename: nil)
      case type.to_s
      when "email", "text" then from_text(content.to_s)
      when "pdf" then from_pdf(content)
      when "xlsx", "excel" then from_xlsx(content, filename: filename)
      when "spreadsheet", "csv"
        filename.to_s.match?(/\.xlsx?\z/i) ? from_xlsx(content, filename: filename) : from_csv(content.to_s, filename: filename)
      else
        Extraction.new(lines: [], warnings: ["unsupported source type: #{type}"], pages: nil, rows: nil, source_type: type.to_s)
      end
    end

    def self.from_text(text)
      lines = text.each_line.map(&:rstrip).each_with_index.filter_map do |raw, i|
        next if raw.strip.empty?

        Line.new(text: raw.strip, location: "line #{i + 1}")
      end
      Extraction.new(lines: lines, warnings: [], pages: nil, rows: nil, source_type: "email")
    end

    def self.from_pdf(bytes)
      require PDF_TEXT_PATH unless defined?(PdfText)
      result = PdfText.extract(bytes)
      text = result.respond_to?(:text) ? result.text : result.to_s
      pages = result.respond_to?(:page_count) ? result.page_count : nil
      warnings = []
      warnings << "the PDF has no extractable text; it may be scanned and needs OCR" if text.strip.empty?
      lines = text.each_line.map(&:rstrip).each_with_index.filter_map do |raw, i|
        next if raw.strip.empty?

        Line.new(text: raw.strip, location: "pdf line #{i + 1}")
      end
      Extraction.new(lines: lines, warnings: warnings, pages: pages, rows: nil, source_type: "pdf")
    rescue StandardError => e
      reason = e.respond_to?(:reason) ? e.reason : e.message
      Extraction.new(lines: [], warnings: ["could not read the PDF: #{reason}"], pages: nil, rows: nil, source_type: "pdf")
    end

    # Excel through the roo gem. Every sheet is read; each row becomes one line with its sheet and row number.
    def self.from_xlsx(bytes, filename: nil)
      require "roo"
      require "tempfile"
      file = Tempfile.new(["rfq", ".xlsx"], binmode: true)
      file.write(bytes.respond_to?(:read) ? bytes.read : bytes.to_s)
      file.flush
      book = Roo::Spreadsheet.open(file.path, extension: :xlsx)
      lines = []
      warnings = []
      total_rows = 0
      book.sheets.each do |sheet_name|
        sheet = book.sheet(sheet_name)
        next if sheet.first_row.nil?

        (sheet.first_row..sheet.last_row).each do |r|
          total_rows += 1
          cells = (sheet.first_column..sheet.last_column).map { |c| sheet.cell(r, c) }
          joined = rows_to_text(cells)
          next if joined.empty?
          next if r == sheet.first_row && header_row?(joined)

          lines << Line.new(text: joined, location: "sheet #{sheet_name}, row #{r}")
        end
      end
      warnings << "#{filename || 'the workbook'} has no rows with text" if lines.empty?
      Extraction.new(lines: lines, warnings: warnings, pages: nil, rows: total_rows, source_type: "spreadsheet")
    rescue LoadError
      Extraction.new(lines: [], warnings: ["Excel reading needs the roo gem; save the file as CSV"], pages: nil, rows: nil, source_type: "spreadsheet")
    rescue StandardError => e
      Extraction.new(lines: [], warnings: ["could not read the Excel file: #{e.message}"], pages: nil, rows: nil, source_type: "spreadsheet")
    ensure
      file&.close!
    end

    def self.rows_to_text(cells)
      cells.compact.map { |c| c.is_a?(Float) && c == c.to_i ? c.to_i.to_s : c.to_s }.map(&:strip).reject(&:empty?).join(" ")
    end

    def self.header_row?(joined)
      joined.match?(/\b(description|item|material|qty|quantity|part)\b/i) && !joined.match?(/\d/)
    end

    def self.from_csv(text, filename: nil)
      require "csv" # bundled gem in Ruby 3.4; the app adds it to its Gemfile when it loads this library

      rows = CSV.parse(text)
      lines = rows.each_with_index.filter_map do |cells, i|
        joined = cells.compact.map(&:to_s).map(&:strip).reject(&:empty?).join(" ")
        next if joined.empty?
        next if i.zero? && header_row?(joined)

        Line.new(text: joined, location: "row #{i + 1}")
      end
      Extraction.new(lines: lines, warnings: [], pages: nil, rows: rows.size, source_type: "spreadsheet")
    rescue CSV::MalformedCSVError => e
      Extraction.new(lines: [], warnings: ["could not read the spreadsheet: #{e.message}"], pages: nil, rows: nil, source_type: "spreadsheet")
    end
  end
end
