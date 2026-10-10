require "test_helper"

class LineOpeningTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    @held = @quote.quote_lines.second
    @other = @quote.quote_lines.third
  end

  test "line links remain normal accessible filtered navigation with enhancement hooks" do
    get quote_path(@quote, status: "attention", line: @held.id)
    assert_response :success
    assert_select "[data-review-root]", count: 1
    assert_select "[data-review-status][role=status]", count: 1
    assert_select "tr[data-review-row='#{@held.id}'].is-selected" do
      assert_select "a[data-review-link][aria-expanded=true][aria-controls=line-detail]"
    end
    assert_select "a[data-review-link][href=?]", quote_path(@quote, status: "attention", line: @other.id)
    assert_select "#line-detail-heading[tabindex='-1']", text: /Line 2:/
    assert_select ".review__source mark", text: @held.original_text
  end

  test "fetchable full response selects new detail and original highlights together" do
    get quote_path(@quote, status: "attention", line: @other.id), headers: {"Accept" => "text/html"}
    assert_response :success
    assert_select "tr[data-review-row='#{@other.id}'].is-selected"
    assert_select "#line-detail", count: 1
    assert_select "#line-detail-heading", text: /Line 3:/
    assert_select ".review__source mark", text: @other.original_text
    assert_select ".review-navigation a[aria-current=page]", text: /Attention needed/
    assert_select "[data-review-root] form", minimum: 1
  end
end
