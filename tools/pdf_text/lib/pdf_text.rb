# frozen_string_literal: true

require 'pdf-reader'
require 'stringio'

# Pulls the text out of a PDF. Bytes in, a Result (text + page count) out, or a
# PdfText::Error whose #reason is a plain sentence you can show a user.
#
#   result = PdfText.extract(File.binread('resume.pdf'))
#   result.text   # => "Jane Doe\n\nExperience ..."
#   result.pages  # => 2
#
# Ported from Steady Thread's plan-document upload (PlanDocuments::UploadValidator,
# Extractors::PdfExtractor, TextCleaner). Pure Ruby, no Rails.
module PdfText
  # Fails the extraction outright above this many characters of cleaned text.
  MAX_EXTRACTED_CHARS = 200_000

  # Reject files bigger than this before parsing. The whole file is read into memory.
  MAX_BYTES = 100 * 1024 * 1024

  # A real PDF opens with "%PDF-". The spec allows (rarely) junk before the header,
  # so the signature may appear anywhere in the first 1024 bytes.
  PDF_SIGNATURE = '%PDF-'.b.freeze
  PDF_HEADER_SCAN_BYTES = 1024

  Result = Struct.new(:text, :pages, keyword_init: true)

  # Base class. Catch PdfText::Error, read #reason, done.
  class Error < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super
    end
  end

  class EmptyFileError < Error
    def initialize = super('this file is empty')
  end

  class FileTooLargeError < Error
    def initialize = super('this file is too large')
  end

  # The bytes carry no "%PDF-" header: something else renamed .pdf.
  class NotAPdfError < Error
    def initialize = super("this file isn't a PDF")
  end

  class ProtectedFileError < Error
    def initialize = super('this PDF is password protected')
  end

  class CorruptedOrComplexError < Error
    def initialize = super('file looks corrupted or is too complex to read')
  end

  # The PDF parses but has no text layer (a scanned, image-only document). The file
  # is not empty; its text just can't be read. Running OCR is the fix.
  class UnreadableTextError < Error
    def initialize = super("couldn't read this file's text")
  end

  class DocumentTooLargeError < Error
    def initialize = super('this document has too much text')
  end

  def self.extract(bytes)
    bytes = (bytes || '').b
    validate!(bytes)

    pages = read_pages(bytes)
    page_texts = pages.map { |text| text.to_s.strip }.reject(&:empty?)
    raise UnreadableTextError if page_texts.empty?

    text = clean(page_texts.join("\n\n"))
    raise UnreadableTextError if text.empty?
    raise DocumentTooLargeError if text.length > MAX_EXTRACTED_CHARS

    Result.new(text: text, pages: pages.size)
  end

  # A cheap header check before any parsing. Whether the PDF is actually readable
  # (real text vs. a scan, encrypted, malformed) is read_pages' job.
  def self.validate!(bytes)
    raise EmptyFileError if bytes.empty?
    raise FileTooLargeError if bytes.bytesize > MAX_BYTES
    raise NotAPdfError unless bytes[0, PDF_HEADER_SCAN_BYTES].include?(PDF_SIGNATURE)
  end

  # pdf-reader can raise many errors on hostile or damaged input. They map to:
  #   EncryptedPDFError (a subclass of UnsupportedFeatureError, so rescued first)
  #     -> ProtectedFileError
  #   MalformedPDFError / UnsupportedFeatureError / anything else
  #     -> CorruptedOrComplexError
  def self.read_pages(bytes)
    PDF::Reader.new(StringIO.new(bytes)).pages.map(&:text)
  rescue PDF::Reader::EncryptedPDFError
    raise ProtectedFileError
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    raise CorruptedOrComplexError
  rescue StandardError
    # Lower-level parsers can raise ArgumentError, Errno, encoding errors, and more
    # on broken input. Treat all of them as corrupted rather than leak a stack trace.
    raise CorruptedOrComplexError
  end

  # Normalizes line endings, strips trailing spaces, and collapses runs of blank
  # lines to one.
  def self.clean(text)
    lines = text.to_s.gsub("\r\n", "\n").gsub("\r", "\n").split("\n", -1).map(&:rstrip)

    collapsed = []
    blank_run = 0
    lines.each do |line|
      if line.empty?
        blank_run += 1
        collapsed << line if blank_run <= 1
      else
        blank_run = 0
        collapsed << line
      end
    end

    collapsed.join("\n").strip
  end

  private_class_method :read_pages
end
