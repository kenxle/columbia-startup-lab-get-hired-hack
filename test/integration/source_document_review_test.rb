require "test_helper"

class SourceDocumentReviewTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
  end

  test "complete original body remains visible with selected evidence highlighted in place" do
    line = @quote.quote_lines.second
    @quote.update!(source_text: "From: Buyer\n<script>unsafe()</script>\n#{line.original_text}\nPlease send paperwork.\nThanks")
    get quote_path(@quote, line: line.id)
    assert_select ".review__source pre", count: 1
    assert_select ".review__source pre", text: @quote.source_text
    assert_select ".review__source mark", text: line.original_text
    assert_select ".review__source script", count: 0
    assert_select ".source-excerpt", count: 0
    refute_includes response.body, "as written</h3>"
  end

  test "CSV attachment is shown with email body and original download" do
    @quote.update!(source_bytes: "Description,Qty\nS-330 steel shot,100\n", original_filename: "buyer.csv")
    get quote_path(@quote)
    assert_select ".review__source pre", count: 2
    assert_select ".review__source pre", text: /Description,Qty/
    assert_select ".review__source a[href=?]", source_quote_path(@quote)
  end

  test "unreadable upload shows warning and download rather than parsed line excerpts" do
    @quote.update!(source_text: nil, source_bytes: "%PDF-broken", original_filename: "buyer.pdf")
    get quote_path(@quote)
    assert_select ".review__source pre", count: 0
    assert_select ".review__source [role=note]", text: /Download the original file/
    assert_select ".review__source a[href=?]", source_quote_path(@quote)
    assert_select ".source-excerpt", count: 0
  end
end
