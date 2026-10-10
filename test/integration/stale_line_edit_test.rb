require "test_helper"

class StaleLineEditTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    @line = @quote.quote_lines.first
  end

  test "an old tab cannot overwrite a newer quantity" do
    get quote_path(@quote, line: @line.id)
    old_version = @quote.reload.review_revision
    assert_select '.line-form input[name="reviewed_version"]', value: old_version
    @line.apply_manual_edit("quantity" => "999")
    before = @line.reload.attributes
    patch quote_quote_line_path(@quote, @line), params: {reviewed_version: old_version,
      quote_line: {quantity: "20", notes: "From old tab"}}
    assert_response :redirect
    follow_redirect!
    assert_includes response.body, "Your changes were not saved."
    assert_equal before, @line.reload.attributes
    refute @quote.reload.approved?
  end

  test "stale edits cannot clear newer approval and a current save still works" do
    old_version = @quote.review_revision
    @quote.approve!
    approved = @quote.reload.attributes
    patch quote_quote_line_path(@quote, @line), params: {reviewed_version: old_version,
      quote_line: {notes: "From old tab"}}
    assert_response :redirect
    assert_equal approved, @quote.reload.attributes
    assert @quote.approved?
    patch quote_quote_line_path(@quote, @line), params: {reviewed_version: @quote.review_revision,
      quote_line: {notes: "Current edit"}}
    assert_response :redirect
    assert_equal "Current edit", @line.reload.notes
    refute @quote.reload.approved?
  end

  test "missing and malformed revision tokens never save a line" do
    [nil, "", {bad: "input"}].each do |version|
      before = @line.reload.attributes
      patch quote_quote_line_path(@quote, @line), params: {reviewed_version: version,
        quote_line: {notes: "Must not save"}}
      assert_response :redirect
      assert_equal before, @line.reload.attributes
    end
  end
end
