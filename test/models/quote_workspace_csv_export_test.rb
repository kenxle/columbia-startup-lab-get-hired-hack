require "test_helper"

class QuoteWorkspaceCsvExportTest < ActiveSupport::TestCase
  LEADING_FORMULA_CELL = /(\A|,|\r\n)"[=+\-@\t\r]/

  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "csv-export-test-workspace")
  end

  test "formula prefixes are escaped" do
    escape = QuoteWorkspace::CsvExport.method(:escape_formula)

    assert_equal "'=HYPERLINK(\"http://example.test\")", escape.call("=HYPERLINK(\"http://example.test\")")
    assert_equal "'+SUM(A1:A9)", escape.call("+SUM(A1:A9)")
    assert_equal "'-2+3", escape.call("-2+3")
    assert_equal "'@cmd", escape.call("@cmd")
    assert_equal "'\t=1", escape.call("\t=1")
    assert_equal "'  =1", escape.call("  =1")
    assert_equal "'＝1", escape.call("＝1")
    assert_equal "304 stainless", escape.call("304 stainless")
    assert_equal "", escape.call(nil)
  end

  test "export is unavailable before approval" do
    assert_raises(QuoteWorkspace::CsvExport::NotApproved) { QuoteWorkspace::CsvExport.new(@quote).to_csv }
  end

  test "approved sample export prices ready lines and leaves held lines unpriced" do
    @quote.approve!
    csv_export = QuoteWorkspace::CsvExport.new(@quote.reload)
    output = csv_export.to_csv

    refute_match(/SAMPLE/, csv_export.filename)
    assert output.start_with?(%("Quote reference",))
    assert_includes output, %("#{@quote.reference}")
    assert_includes output, %("232.00","4640.00")
    assert_includes output, %("Subtotal, Ready lines only (USD)","4640.00")
    assert_includes output, "Mill test report"

    rows = output.split("\r\n")
    held_row = rows.find { |row| row.start_with?(%("2","Question to send")) }
    no_match_row = rows.find { |row| row.start_with?(%("3","No match")) }
    assert held_row
    assert no_match_row
    assert_includes held_row, "Which material and grade do you need?"
    assert_includes no_match_row, "does not match an item in our sample catalog"
    refute_match(/\d+\.\d{2}"/, held_row.sub(/"10"/, ""), "held lines carry no price")
    refute_match(/\d+\.\d{2}"/, no_match_row.sub(/"2"/, ""), "held lines carry no price")
  end

  test "user-controlled strings cannot start a formula" do
    @quote.update!(title: "=cmd|' /C calc'!A0", buyer_name: "@SUM(1+1)")
    ready_line = @quote.quote_lines.first
    assert ready_line.apply_manual_edit("description" => "+HYPERLINK(\"http://example.test\")", "notes" => "-1+1")
    held_line = @quote.quote_lines.second
    assert held_line.apply_manual_edit("clarification_question" => "=IMPORTXML(\"http://example.test\")")
    @quote.reload.approve!

    output = QuoteWorkspace::CsvExport.new(@quote.reload).to_csv

    refute_match LEADING_FORMULA_CELL, output
    assert_includes output, %("'=cmd|' /C calc'!A0")
    assert_includes output, %("'@SUM(1+1)")
    assert_includes output, %("'+HYPERLINK(""http://example.test"")")
    refute_includes output, "-1+1", "internal notes must not reach the buyer"
    assert_includes output, %("'=IMPORTXML(""http://example.test"")")
  end

  test "sub-cent override exports exact unit price without the old benchmark or internal note" do
    line = @quote.quote_lines.first
    line.apply_manual_edit("unit_price" => "232.005", "notes" => "Private supplier negotiation")
    @quote.reload.approve!
    output = QuoteWorkspace::CsvExport.new(@quote.reload).to_csv
    assert_includes output, %("232.0050","4640.10")
    refute_includes output, "Private supplier negotiation"
    refute_includes output, "Sample price table (as of"
  end

  test "cells with quotes, commas and newlines stay in one field" do
    row = QuoteWorkspace::CsvExport.encode_row([ "a \"quoted\" value", "one, two", "line\nbreak" ])

    assert_equal %("a ""quoted"" value","one, two","line\nbreak"\r\n), row
  end

  test "decimal formatting avoids floating point" do
    assert_equal "4640.00", QuoteWorkspace::CsvExport.format_decimal(BigDecimal("4640"), 2)
    assert_equal "0.10", QuoteWorkspace::CsvExport.format_decimal(BigDecimal("0.1"), 2)
    assert_equal "1234567890.13", QuoteWorkspace::CsvExport.format_decimal(BigDecimal("1234567890.125"), 2)
    assert_equal "20", QuoteWorkspace::CsvExport.format_quantity(BigDecimal("20"))
    assert_equal "2.5", QuoteWorkspace::CsvExport.format_quantity(BigDecimal("2.5"))
  end
end
