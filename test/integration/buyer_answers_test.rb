require "test_helper"

class BuyerAnswersTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(client: nil, catalog: CatalogMatch::Catalog.new(%w[rudco metals]), service: CatalogMatch::Matcher)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: RfqProcessing.process(content: "S-330 steel shot, lb", matcher: matcher, llm: false))
    @line = @quote.quote_lines.first
    @params = {quote_line_id: @line.id, reviewed_version: @quote.reload.review_revision,
      revision_id: @quote.processing_revision["id"], free_text: "100 lb"}
  end

  test "rep submits an answer and returns to the same line for review" do
    post quote_buyer_answers_path(@quote), params: @params
    assert_redirected_to quote_path(@quote, line: @line.id)
    assert @line.reload.quotable?
    refute @quote.reload.approved?
  end

  test "another session cannot answer a quote" do
    browser = open_session
    browser.post quote_buyer_answers_path(@quote), params: @params
    assert_equal 404, browser.response.status
    refute @line.reload.quotable?
  end

  test "a line from another quote cannot be answered" do
    other = QuoteWorkspace::Demo.create!(workspace_token: @quote.workspace_token)
    post quote_buyer_answers_path(@quote), params: @params.merge(quote_line_id: other.quote_lines.first.id)
    assert_response :not_found
  end

  test "stale or blank answers redirect with actionable error and preserve held state" do
    post quote_buyer_answers_path(@quote), params: @params.merge(revision_id: "old")
    assert_redirected_to quote_path(@quote, line: @line.id)
    assert_match(/changed/, flash[:alert])
    post quote_buyer_answers_path(@quote), params: @params.merge(free_text: " ")
    assert_redirected_to quote_path(@quote, line: @line.id)
    refute @line.reload.quotable?
  end
end
