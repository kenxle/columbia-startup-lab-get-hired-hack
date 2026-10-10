require "test_helper"

class SourceEvidenceDisclosureTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
  end

  test "source pill starts closed in the quote header and retains files counts and warnings" do
    @quote.assign_processing_evidence(source: { "type" => "pdf", "filename" => "request.pdf", "pages" => 0, "rows" => 12 },
      warnings: ["Page 1 needs review."]).save!
    get quote_path(@quote)
    assert_response :success

    assert_select ".page-header details.processing-evidence:not([open])", count: 1 do
      assert_select "summary.processing-evidence__trigger", text: /Source: PDF.*1 warning/m
      assert_select 'summary[aria-controls=?]', "processing-evidence-drawer-#{@quote.id}"
      assert_select 'div[role="region"][aria-labelledby=?]', "processing-evidence-heading-#{@quote.id}"
      assert_select "dt", "Source type"
      assert_select "dd", "pdf"
      assert_select "dd", "request.pdf"
      assert_select "dd", "0"
      assert_select "dd", "12"
      assert_select "li", "Page 1 needs review."
    end
    assert_select ".panel.processing-evidence", count: 0
    assert_includes response.body, "excluded from buyer exports"
  end

  test "run details and untrusted evidence remain visible as escaped text" do
    malicious = '<script>alert("evidence")</script>'
    @quote.assign_processing_evidence(source: { "type" => "email", "filename" => malicious }, warnings: [malicious]).save!
    @quote.update!(original_filename: "saved-attachment.pdf", processing_revision: { "id" => "revision-with-source" })
    run = @quote.processing_runs.create!(status: "failed", requested_revision: @quote.review_revision,
      source_revision: @quote.review_revision, queued_at: Time.current, finished_at: Time.current,
      source_type: "pdf", source_filename: malicious, error_message: malicious, warnings: ["Run warning"])
    get quote_path(@quote)
    assert_response :success
    assert_select ".processing-evidence script, .processing-evidence img", count: 0
    assert_select ".processing-evidence summary", text: /Source: email/
    assert_select ".processing-evidence dd", text: malicious, count: 2
    assert_select ".processing-evidence dd", "saved-attachment.pdf"
    assert_select ".processing-evidence dd", run.id.to_s
    assert_select ".processing-evidence dd", "Failed"
    assert_select ".processing-evidence .mono", "revision-with-source"
    assert_select ".processing-evidence__error", malicious
    assert_select ".processing-evidence li", "Run warning"
  end

  test "active processing status stays outside the collapsed source details" do
    @quote.processing_runs.create!(status: "running", requested_revision: @quote.review_revision,
      source_revision: @quote.review_revision, queued_at: Time.current, started_at: Time.current, source_type: "text")
    get quote_path(@quote)
    assert_response :success
    assert_select ".processing-evidence summary", text: /Source: text/
    assert_select ".processing-run__status", /Running/
    assert_select ".processing-run a", "Refresh processing status"
    assert_select ".processing-evidence .processing-run", count: 0
  end

  test "missing extraction metadata does not invent a source pill" do
    get quote_path(@quote)
    assert_response :success
    assert_select ".processing-evidence", count: 0
  end

  test "collapsing source evidence does not move internal details into buyer exports" do
    @quote.assign_processing_evidence(source: { "type" => "pdf", "filename" => "PRIVATE-SOURCE-FILE" },
      warnings: ["PRIVATE-SOURCE-WARNING"]).save!
    @quote.approve!
    get quote_path(@quote)
    assert_select ".processing-evidence dd", "PRIVATE-SOURCE-FILE"

    exports = [QuoteWorkspace::CsvExport.new(@quote).to_csv, QuoteWorkspace::FinalQuote.new(@quote).body,
      QuoteWorkspace::BuyerQuestionDraft.new(@quote).body]
    exports.each do |value|
      refute_includes value, "PRIVATE-SOURCE-FILE"
      refute_includes value, "PRIVATE-SOURCE-WARNING"
    end
  end
end
