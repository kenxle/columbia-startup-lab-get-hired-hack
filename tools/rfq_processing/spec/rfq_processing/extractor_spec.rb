# frozen_string_literal: true

require "zip"

RSpec.describe RfqProcessing::Extractor do
  # A minimal .xlsx built by hand: one sheet, inline strings, so no fixture binary is committed.
  def build_xlsx(rows)
    sheet_rows = rows.each_with_index.map do |cells, r|
      cols = cells.each_with_index.map do |value, c|
        ref = "#{('A'.ord + c).chr}#{r + 1}"
        if value.is_a?(Numeric)
          %(<c r="#{ref}"><v>#{value}</v></c>)
        else
          %(<c r="#{ref}" t="inlineStr"><is><t>#{value.to_s.encode(xml: :text)}</t></is></c>)
        end
      end.join
      %(<row r="#{r + 1}">#{cols}</row>)
    end.join
    files = {
      "[Content_Types].xml" => %(<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>),
      "_rels/.rels" => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>),
      "xl/workbook.xml" => %(<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="RFQ" sheetId="1" r:id="rId1"/></sheets></workbook>),
      "xl/_rels/workbook.xml.rels" => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>),
      "xl/styles.xml" => %(<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>),
      "xl/worksheets/sheet1.xml" => %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{sheet_rows}</sheetData></worksheet>)
    }
    io = Zip::OutputStream.write_buffer do |zip|
      files.each { |name, body| zip.put_next_entry(name); zip.write(body) }
    end
    io.string
  end

  it "reads an .xlsx row by row, skips the header, and keeps the sheet and row as the location" do
    bytes = build_xlsx([["Item", "Description", "Qty"], [1, "304 SS sheet 16ga 4x8", 20], [2, "Steel shot S-330", "2,000 lb"]])
    extraction = described_class.extract(bytes, type: "spreadsheet", filename: "rfq.xlsx")
    expect(extraction.warnings).to be_empty
    expect(extraction.lines.map(&:text)).to eq(["1 304 SS sheet 16ga 4x8 20", "2 Steel shot S-330 2,000 lb"])
    expect(extraction.lines.first.location).to eq("sheet RFQ, row 2")
    expect(extraction.rows).to eq(3)
  end

  it "runs a workbook through the whole pipeline" do
    bytes = build_xlsx([["Description", "Qty"], ["304 SS sheet 16ga 4x8", "20 sheets"]])
    result = RfqProcessing.process(content: bytes, type: "spreadsheet", filename: "rfq.xlsx", catalog: [])
    expect(result["source"]["type"]).to eq("spreadsheet")
    expect(result["lines"].first["spec"]["thickness"]).to eq(0.0625)
    expect(result["lines"].first["evidence"]["thickness"]["location"]).to start_with("sheet RFQ, row 2")
  end

  it "reads CSV and warns on an empty workbook" do
    csv = described_class.extract("Description,Qty\n304 SS sheet 16ga 4x8,20\n", type: "csv")
    expect(csv.lines.map(&:text)).to eq(["304 SS sheet 16ga 4x8 20"])
    empty = described_class.extract(build_xlsx([]), type: "xlsx", filename: "empty.xlsx")
    expect(empty.warnings.first).to include("no rows with text")
  end
end
