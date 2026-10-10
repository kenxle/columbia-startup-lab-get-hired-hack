require "test_helper"

class ReviewNavigationTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(Integer(response.location[%r{/quotes/(\d+)}, 1]))
    @ready, @held, @unmatched = @quote.quote_lines.to_a
  end

  test "filters show whole quote counts and default to all" do
    get quote_path(@quote)

    assert_response :success
    assert_select ".review-navigation[aria-label='Quote line review']" do
      assert_select "a[aria-current='page']", text: /All\s+3/
      assert_select "a", text: /Attention needed\s+2/
      assert_select "a", text: /Ready\s+1/
    end
    assert_select ".lines-table tbody tr", count: 3
    assert_select ".review-questions-link[href=?]", quote_buyer_questions_path(@quote), text: "Review buyer questions (2)"
  end

  test "attention preserves original numbering and hides held prices" do
    @held.update!(unit_price: 999)
    get quote_path(@quote, status: "attention", line: @ready.id)

    assert_response :success
    assert_equal %w[2 3], css_select(".lines-table tbody tr > td:first-child").map(&:text)
    assert_select ".lines-table tbody tr.is-held", count: 2
    assert_select "#line-detail-heading", text: /Line 2:/
    assert_select ".lines-table tbody", text: /999/, count: 0
    assert_select ".lines-table .row-link[href=?]", quote_path(@quote, status: "attention", line: @unmatched.id)
    assert_select ".review-navigation a[aria-current='page']", text: /Attention needed/
  end

  test "ready view retains whole quote subtotal and all approval questions" do
    get quote_path(@quote, status: "ready", line: @held.id)

    assert_select ".lines-table tbody tr", count: 1
    assert_select "#line-detail-heading", text: /Line 1:/
    assert_select ".summary__item--total", text: /4,640\.00/
    assert_select ".lines-table tfoot", text: /4,640\.00/
    assert_select ".held-questions__list li", count: 2
    assert_select "label[for='reviewed']", text: /2 held lines/
    assert_select ".summary__item:nth-child(2) dd", text: "3"
  end

  test "attention view still shows subtotal from ready lines outside filter" do
    get quote_path(@quote, status: "attention")

    assert_select ".summary__item--total", text: /4,640\.00/
    assert_select ".lines-table tfoot", text: /4,640\.00/
    assert_select "label[for='reviewed']", text: /1 ready line/
  end

  test "unknown or structured status and unrelated line parameters fall back safely" do
    ["unknown", { invalid: "ready" }, ["ready"]].each do |invalid|
      get quote_path(@quote), params: { status: invalid, line: "999999" }
      assert_response :success
      assert_select ".lines-table tbody tr", count: 3
      assert_select "#line-detail-heading", text: /Line 1:/
      assert_select ".review-navigation a[aria-current='page']", text: /All/
    end
  end

  test "empty ready filter has no selected line but retains approval blockers" do
    @ready.update!(state: "needs_buyer", clarification_question: "Confirm the grade.")
    get quote_path(@quote, status: "ready")

    assert_response :success
    assert_select ".empty-state__body", text: "No lines in this view."
    assert_select "#line-detail", count: 0
    assert_select ".lines-table", count: 0
    assert_select ".held-questions__list li", count: 3
    assert_select ".approval", text: /Not ready for approval/
    assert_select "a[href=?]", quote_path(@quote, status: "all"), text: "Show all lines"
  end

  test "next held line advances through all held lines and wraps" do
    [[@ready, "ready", @held], [@held, "attention", @unmatched], [@unmatched, "all", @held]].each do |selected, status, expected|
      get quote_path(@quote, status: status, line: selected.id)
      assert_select ".review-navigation__next[href=?]", quote_path(@quote, status: "attention", line: expected.id)
      assert_select ".review-navigation__next[aria-label=?]", "Next held line, line #{expected.position}"
    end
  end

  test "empty attention filter omits next held and buyer questions actions" do
    @held.destroy!
    @unmatched.destroy!
    get quote_path(@quote, status: "attention")

    assert_response :success
    assert_select "#line-detail", count: 0
    assert_select ".review-navigation__next", count: 0
    assert_select ".review-questions-link", count: 0
    assert_select ".summary__item--total", text: /4,640\.00/
    assert_select ".approval input[type='submit']", count: 1
  end

  test "filter links remain session scoped" do
    browser = open_session
    %w[all attention ready].each do |status|
      browser.get quote_path(@quote, status: status, line: @held.id)
      assert_equal 404, browser.response.status
    end
  end

  test "invalid edit still renders all rows and validation errors" do
    patch quote_quote_line_path(@quote, @ready), params: { quote_line: { quantity: "invalid" } }

    assert_response 422
    assert_select ".lines-table tbody tr", count: 3
    assert_select "#line-detail .form-errors", count: 1
    assert_select ".review-navigation a[aria-current='page']", text: /All/
  end

  test "successful saves preserve each allowed review filter" do
    [["attention", @held], ["ready", @ready], ["all", @unmatched]].each do |status, line|
      get quote_path(@quote, status: status, line: line.id)
      assert_select '.line-form input[name="status"][value=?]', status
      patch quote_quote_line_path(@quote, line), params: { status: status, quote_line: { notes: "Reviewed #{status}" } }
      assert_redirected_to quote_path(@quote, line: line.id, status: status)
    end
  end

  test "failed save preserves filter rows selection and hidden context" do
    [["attention", @held, 2], ["ready", @ready, 1]].each do |status, line, count|
      patch quote_quote_line_path(@quote, line), params: { status: status, quote_line: { quantity: "invalid" } }
      assert_response 422
      assert_select ".lines-table tbody tr", count: count
      assert_select "#line-detail .form-errors", count: 1
      assert_select "#line-detail-heading", text: /Line #{line.position}:/
      assert_select '.line-form input[name="status"][value=?]', status
      assert_select '.review-navigation a[aria-current="page"][href=?]', quote_path(@quote, status: status, line: line.id)
    end
  end

  test "untrusted navigation parameters are ignored" do
    ["https://evil.example", { url: "https://evil.example" }, ["buyer_questions"]].each do |invalid|
      patch quote_quote_line_path(@quote, @held), params: { status: invalid, return_to: invalid, quote_line: { notes: "Safe edit" } }
      assert_redirected_to quote_path(@quote, line: @held.id)
      get quote_path(@quote, line: @held.id), params: { return_to: invalid }
      assert_select '.line-form input[name="return_to"]', count: 0
    end
  end

  test "the only held line is not its own next line" do
    @unmatched.destroy!
    get quote_path(@quote, status: "attention", line: @held.id)
    assert_select ".review-navigation__next", count: 0
    get quote_path(@quote, status: "ready", line: @ready.id)
    assert_select ".review-navigation__next[href=?]", quote_path(@quote, status: "attention", line: @held.id)
  end
end
