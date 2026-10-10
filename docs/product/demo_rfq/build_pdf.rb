# Builds northline_rfq_2026-1010.pdf from the CSV next to it.
#   bin/rails runner docs/product/demo_rfq/build_pdf.rb
require "csv"
require "prawn"

dir = File.expand_path(__dir__)
rows = CSV.read(File.join(dir, "northline_rfq_2026-1010.csv"), headers: true)

Prawn::Document.generate(File.join(dir, "northline_rfq_2026-1010.pdf"), page_size: "LETTER", margin: 54) do |pdf|
  pdf.font_size 10
  pdf.text "Northline Fabrication", size: 16, style: :bold
  pdf.text "Purchasing, Newark, NJ"
  pdf.move_down 12
  pdf.text "Request for Quotation 2026-1010", size: 13, style: :bold
  pdf.text "To: RudCo quotes desk     Ship to: US 07105 (Newark, NJ)     Delivery: end of month"
  pdf.move_down 8
  pdf.text "MTRs required on all steel. Send a COA with each lot of abrasive."
  pdf.move_down 12
  table = [ rows.headers ] + rows.map(&:fields)
  widths = [ 30, 250, 60, 50, 114 ]
  table.each_with_index do |row, index|
    y = pdf.cursor
    x = 0
    row.each_with_index do |cell, column|
      pdf.text_box cell.to_s, at: [ x, y ], width: widths[column] - 6, height: 14, style: (index.zero? ? :bold : :normal)
      x += widths[column]
    end
    pdf.move_down 16
  end
  pdf.move_down 16
  pdf.text "Contact: Dana Ortiz, purchasing@northline-fab.example"
end
puts "Wrote #{File.join(dir, 'northline_rfq_2026-1010.pdf')}"
