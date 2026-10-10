require "prawn"

module QuoteWorkspace
  class PdfExport
    # Exact specifications must never silently become replacement glyphs.
    class UnsupportedGlyph < StandardError; end

    FONT_ROOT = Rails.root.join("app/assets/fonts/noto").freeze
    INK = "1A212D".freeze
    MUTED = "454E5E".freeze
    BLUE = "0063E6".freeze

    def initialize(quote)
      @final_quote = FinalQuote.new(quote)
    end

    def filename
      @final_quote.with_snapshot { |data| "#{data[:basename]}.pdf" }
    end

    def to_pdf
      @final_quote.with_snapshot do |data|
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 82, 46, 66, 46 ],
          info: { Title: "Quote #{data[:reference]}", Creator: "Quote Desk" })
        pdf.font_families.update(
          "Noto" => { normal: FONT_ROOT.join("NotoSans-Regular.ttf").to_s, bold: FONT_ROOT.join("NotoSans-Bold.ttf").to_s },
          "Symbols" => { normal: FONT_ROOT.join("NotoSansSymbols2-Regular.ttf").to_s, bold: FONT_ROOT.join("NotoSansSymbols2-Regular.ttf").to_s }
        )
        pdf.font("Noto", size: 9)
        verify_glyphs!(pdf, data)
        decorate_pages(pdf, data)
        text(pdf, data[:title], size: 20, style: :bold, color: INK)
        text(pdf, "Buyer: #{data[:buyer]}", color: MUTED) if data[:buyer].present?
        text(pdf, "Approved: #{data[:approved_at]}", size: 8, color: MUTED)
        pdf.move_down 12
        if data[:sample]
          text(pdf, FinalQuote::SAMPLE_NOTICE, size: 9, style: :bold, color: "7F4205")
          pdf.move_down 8
        end
        text(pdf, "Ready-line subtotal", size: 10, color: MUTED)
        text(pdf, "USD #{data[:subtotal]}", size: 24, style: :bold, color: BLUE)
        text(pdf, "Held lines are unpriced and excluded from this subtotal.", size: 8, color: MUTED)
        pdf.move_down 20
        data[:lines].each { |line| render_line(pdf, line) }
        pdf.move_down 10
        text(pdf, "Requested paperwork records buyer requirements, not certification of stock.", size: 8, color: MUTED)
        pdf.number_pages "Page <page> of <total>", at: [ pdf.bounds.width - 100, -27 ],
          width: 100, align: :right, size: 8, color: MUTED
        pdf.render
      end
    end

    private

    def text(pdf, value, **options)
      height = pdf.height_of(value.to_s, { leading: 3, fallback_fonts: [ "Symbols" ] }.merge(options.except(:color)))
      if height <= pdf.bounds.height && height > pdf.cursor
        pdf.start_new_page
        pdf.text "LINE #{@active_line} / continued", size: 8, color: MUTED if @active_line
        pdf.move_down 8 if @active_line
      end
      pdf.text value.to_s, { color: INK, leading: 3, fallback_fonts: [ "Symbols" ] }.merge(options)
    end

    def decorate_pages(pdf, data)
      pdf.repeat(:all, dynamic: true) do
        pdf.canvas do
          pdf.fill_color BLUE
          pdf.fill_rectangle [ 0, pdf.page.dimensions[3] ], pdf.page.dimensions[2], 6
          pdf.fill_color INK
          pdf.text_box "QUOTE DESK / CONCEPT QUOTE", at: [ 46, pdf.page.dimensions[3] - 28 ],
            width: 320, height: 20, size: 9, style: :bold
          pdf.text_box data[:reference], at: [ pdf.page.dimensions[2] - 180, pdf.page.dimensions[3] - 28 ],
            width: 134, height: 20, align: :right, size: 9
          footer = data[:sample] ? "SAMPLE DATA / Concept quote" : "Concept quote"
          pdf.fill_color MUTED
          pdf.text_box footer, at: [ 46, 40 ], width: 350, height: 18, size: 8
        end
      end
    end

    def render_line(pdf, line)
      @active_line = line[:position]
      pdf.start_new_page if pdf.cursor < 110
      pdf.stroke_color "E5E7EB"
      pdf.stroke_horizontal_rule
      pdf.move_down 12
      text(pdf, "LINE #{line[:position]} / #{line[:status]}", size: 9, style: :bold,
        color: line[:ready] ? BLUE : "7F4205")
      pdf.move_down 4
      text(pdf, line[:description], size: 12, style: :bold)
      line[:spec].each { |label, value| text(pdf, "#{label}: #{value}", size: 9) }
      pdf.move_down 6
      text(pdf, "Quantity: #{line[:quantity]}")
      if line[:ready]
        text(pdf, "Catalog SKU: #{line[:sku]}")
        text(pdf, "Unit price: USD #{line[:unit_price]} | Line total: USD #{line[:total]}", style: :bold)
        text(pdf, "Price source: #{line[:price_source]}", size: 8, color: MUTED)
        if line[:rep_price]
          text(pdf, "Rep-entered price. Previous benchmark claims do not apply.", size: 8, color: MUTED)
        elsif line[:benchmark]["name"].present?
          benchmark = line[:benchmark]
          text(pdf, "Benchmark: #{benchmark['name']}", size: 8, color: MUTED) if benchmark["name"].present?
          text(pdf, "As of: #{benchmark['as_of']}", size: 8, color: MUTED) if benchmark["as_of"].present?
          text(pdf, "Sample benchmark", size: 8, color: "7F4205") if benchmark["kind"] == "sample"
          text(pdf, benchmark["explanation"], size: 8, color: MUTED) if benchmark["explanation"].present?
        else
          text(pdf, "Benchmark: not provided", size: 8, color: MUTED)
        end
      else
        text(pdf, "Unpriced. Excluded from subtotal.", style: :bold, color: "7F4205")
        text(pdf, "Question for the buyer: #{line[:question]}")
      end
      text(pdf, "Lead time: #{line[:lead_time]}")
      text(pdf, "Lead time source: #{line[:lead_time_source]}", size: 8, color: MUTED) if line[:lead_time_source].present?
      if line[:compliance].any?
        text(pdf, "Requested paperwork (not certified): #{line[:compliance].join('; ')}", size: 9)
      end
      pdf.move_down 18
      @active_line = nil
    end

    def verify_glyphs!(pdf, data)
      strings = []
      collect = lambda do |value|
        case value
        when String then strings << value
        when Hash then value.each_value { |entry| collect.call(entry) }
        when Array then value.each { |entry| collect.call(entry) }
        end
      end
      collect.call(data)
      fonts = [ pdf.font("Noto"), pdf.font("Symbols") ]
      missing = strings.join.each_codepoint.uniq.reject do |codepoint|
        [ 9, 10, 13 ].include?(codepoint) || fonts.any? { |font| font.glyph_present?(codepoint.chr(Encoding::UTF_8)) }
      end
      pdf.font("Noto")
      return if missing.empty?

      labels = missing.map { |codepoint| format("U+%04X", codepoint) }.join(", ")
      raise UnsupportedGlyph, "PDF font cannot represent #{labels}. Use the text or CSV export to preserve these characters."
    end
  end
end
