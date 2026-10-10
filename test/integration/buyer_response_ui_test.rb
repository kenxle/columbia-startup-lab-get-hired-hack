require "test_helper"

class BuyerResponseUiTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
  end

  def apply_held_fixture
    result = JSON.parse(Rails.root.join("tools/rfq_processing/spec/fixtures/results/needs_buyer_an3_missing_length.json").read)
    yield result if block_given?
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
    @quote.reload.quote_lines.first
  end

  test "processed held line offers revision bound choices and separate free text on both review screens" do
    line = apply_held_fixture
    [quote_path(@quote, line: line.id), quote_buyer_questions_path(@quote)].each do |path|
      get path
      assert_response :success
      assert_select 'form.buyer-answer__choice-form[action=?][method="post"]', quote_buyer_answers_path(@quote) do
        assert_select 'input[name="quote_line_id"][value=?]', line.id.to_s
        assert_select 'input[name="reviewed_version"][value=?]', @quote.review_revision
        assert_select 'input[name="revision_id"][value=?]', @quote.processing_revision.fetch("id")
        assert_select 'input[type="radio"][name="choice_id"][required]', count: 3
        assert_select '[name="free_text"]', count: 0
        assert_select 'input[type="submit"][value="Apply buyer answer"]'
      end
      assert_select 'form.buyer-answer__text-form[action=?][method="post"]', quote_buyer_answers_path(@quote) do
        assert_select 'textarea[name="free_text"][maxlength="2000"][required]'
        assert_select '[name="choice_id"]', count: 0
      end
      assert_select ".buyer-action", text: /reruns this line and clears quote approval/
      assert_select ".line-form form", count: 0
      assert_select ".buyer-draft__badge", "Draft, not sent" if path == quote_buyer_questions_path(@quote)
    end
  end

  test "choice labels and original buyer phrases remain escaped" do
    malicious = '<img src=x onerror="alert(1)">'
    line = apply_held_fixture do |result|
      result["lines"][0]["processing"]["question_choices"][0]["label"] = malicious
      result["lines"][0]["original_text"] = malicious
    end
    get quote_path(@quote, line: line.id)
    assert_response :success
    assert_select ".buyer-action img, .buyer-action script", count: 0
    assert_select ".buyer-answer__choice-form .checkbox__label", text: malicious
    assert_select ".buyer-term blockquote", text: malicious
  end

  test "unprocessed demo lines explain why buyer answers cannot yet be applied" do
    get quote_buyer_questions_path(@quote)
    assert_response :success
    assert_select ".buyer-answer__unavailable", text: "Process this RFQ before applying a buyer answer.", minimum: 1
    assert_select ".buyer-answer__choice-form, .buyer-answer__text-form", count: 0
  end

  test "rep edits and active processing hide answer submission" do
    line = apply_held_fixture
    line.update!(edited_fields: ["notes"])
    get quote_buyer_questions_path(@quote)
    assert_select ".buyer-answer__unavailable", /rep edits/
    assert_select ".buyer-answer__choice-form, .buyer-answer__text-form", count: 0

    line.update!(edited_fields: [])
    @quote.processing_runs.create!(status: "queued", requested_revision: @quote.review_revision,
      source_revision: @quote.review_revision, queued_at: Time.current)
    get quote_path(@quote, line: line.id)
    assert_select ".buyer-answer__unavailable", /Processing is in progress/
    assert_select ".buyer-answer__choice-form, .buyer-answer__text-form", count: 0
  end

  test "explicit teaching is tied to the buyer and source line and only offers supported fields" do
    line = apply_held_fixture
    get quote_path(@quote, line: line.id)
    assert_response :success
    assert_select ".buyer-term", text: /#{Regexp.escape(@quote.buyer_name)}.*#{Regexp.escape(@quote.reference)}, line #{line.position}/m
    assert_select 'form.buyer-term__form[action=?][method="post"]', quote_buyer_terms_path(@quote) do
      assert_select 'input[name="quote_line_id"][value=?]', line.id.to_s
      assert_select 'input[name="reviewed_version"][value=?]', @quote.review_revision
      assert_select 'select[name="field"] option' do |options|
        assert_equal %w[material grade temper form finish standard quantity_unit gauge thickness].sort,
          options.map { |option| option["value"] }.sort
      end
      assert_select 'input[name="term"][maxlength="120"][required]'
      assert_select 'input[name="value"][maxlength="200"][required]'
      assert_select 'input[type="submit"][value="Teach buyer phrase"]'
      assert_select 'input[type="checkbox"]', count: 0
      assert_select '[name="client_id"], [name="provenance"], [name="source"]', count: 0
    end

    @quote.update!(buyer_name: nil)
    get quote_path(@quote, line: line.id)
    assert_select ".buyer-term", count: 0
  end
end
