require "test_helper"

class HardwareReviewTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(Integer(response.location[%r{/quotes/(\d+)}, 1]))
  end

  test "hardware fields retain source evidence and can be edited from the review" do
    result = JSON.parse(Rails.root.join("tools/rfq_processing/spec/fixtures/results/ready_an3_bolt.json").read)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
    line = @quote.quote_lines.first
    get quote_path(@quote)

    assert_response :success
    assert_select "input[name='quote_line[spec][part_number]'][value='AN3-13A']"
    assert_select "input[name='quote_line[spec][diameter]'][value='0.1875']"
    assert_select ".field-row", text: /Part number.*Exact AN part number/m
    @quote.approve!
    patch quote_quote_line_path(@quote, line), params: { quote_line: { spec: { drilling: "drilled shank" } } }
    assert_redirected_to quote_path(@quote, line: line.id)
    assert_equal "drilled shank", line.reload.spec["drilling"]
    assert_equal "needs_buyer", line.state
    refute @quote.reload.approved?
  end

  test "metals review does not add unrelated empty hardware fields" do
    get quote_path(@quote)
    assert_select "input[name='quote_line[spec][part_number]']", count: 0
    assert_select "input[name='quote_line[spec][thickness]']", count: 1
  end

  test "hardware CSV columns align with their headings and prices" do
    result = JSON.parse(Rails.root.join("tools/rfq_processing/spec/fixtures/results/ready_an3_bolt.json").read)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
    @quote.approve!
    get export_quote_path(@quote)
    assert_response :success
    rows = response.body.split("\r\n")
    header = rows.find { |row| row.start_with?('"Line","Status"') }
    data = rows.find { |row| row.start_with?('"1","Ready"') }
    # Export quotes every cell. Read complete quoted cells, including escaped quotes.
    cells = ->(row) { row.scan(/"((?:[^"]|"")*)"(?:,|$)/).flatten.map { |cell| cell.gsub('""', '"') } }
    headers, values = cells.call(header), cells.call(data)
    assert_equal headers.length, values.length
    mapped = headers.zip(values).to_h
    assert_equal "AN3-13A", mapped["Part number"]
    assert_equal "0.1875", mapped["Diameter"]
    assert_equal "undrilled shank", mapped["Drilling"]
    assert_equal "100", mapped["Quantity"]
    assert_equal "each", mapped["Unit"]
    assert_equal "AVI-001", mapped["Catalog SKU"]
    assert_equal "0.5650", mapped["Unit price (USD)"]
    assert_equal "56.50", mapped["Line total (USD)"]
  end
end
