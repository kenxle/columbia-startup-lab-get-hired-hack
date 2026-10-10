module QuoteWorkspace
  # Original stored text and complete attachment text, never reconstructed
  # from the processor's filtered item lines.
  class SourceDocument
    MAXIMUM_DISPLAY_CHARACTERS = 200_000
    Result = Struct.new(:sections, :warnings, keyword_init: true)

    def initialize(quote)
      @quote = quote
    end

    def call
      sections = []
      warnings = []
      sections << {label: "Original request", text: @quote.source_text} if @quote.source_text.present?
      if @quote.source_bytes.present?
        begin
          text = attachment_text
          if text.present?
            sections << {label: "Attachment text: #{@quote.original_filename}", text: text}
          else
            warnings << "The attachment has no readable text. Download the original file to review it."
          end
        rescue Unavailable => error
          warnings << error.message
        rescue LoadError, StandardError
          warnings << "The attachment text could not be displayed. Download the original file to review it."
        end
      elsif @quote.original_filename.present?
        warnings << "The original attachment is unavailable. No attachment text is displayed."
      end
      Result.new(sections: sections, warnings: warnings)
    end

    private

    class Unavailable < StandardError; end

    def attachment_text
      extension = File.extname(@quote.original_filename.to_s).downcase
      bytes = @quote.source_bytes
      raise Unavailable, "The attachment is too large to display. Download the original file to review it." if bytes.bytesize > Quote::MAXIMUM_SOURCE_BYTES
      text = case extension
      when ".pdf"
        require Rails.root.join("tools/pdf_text/lib/pdf_text").to_s unless defined?(PdfText)
        PdfText.extract(bytes).text
      when ".csv", ".txt"
        # Display raw CSV including headers, blank rows, and quoted cells.
        # The item extractor intentionally omits some of those source details.
        bytes.dup.force_encoding(Encoding::UTF_8)
      else
        raise Unavailable, "Text preview is unavailable for this attachment type. Download the original file to review it."
      end
      unless text.valid_encoding? && !text.include?("\u0000") && text.length <= MAXIMUM_DISPLAY_CHARACTERS
        raise Unavailable, "The attachment text cannot be displayed completely. Download the original file to review it."
      end
      text
    end
  end
end
