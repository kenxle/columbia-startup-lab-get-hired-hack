require "test_helper"
require "minitest/mock"

class ProcessingRunsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    post quotes_path, params: { quote: { title: "Processing RFQ", source_text: "304 SS sheet 16ga 4x8, 20 sheets, MTRs required" } }
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    # These tests exercise the manual recovery endpoint independently of the
    # automatic intake job, covered by IntakeProcessingTest.
    clear_enqueued_jobs
    ProcessingRun.where(quote_id: @quote.id).delete_all
  end

  def submit_processing(revision = @quote.reload.review_revision)
    post quote_processing_path(@quote), params: { reviewed_version: revision }
  end

  def latest_run
    ProcessingRun.where(quote: @quote).order(id: :desc).first
  end

  test "initial page has guarded action and honest processing capability copy" do
    get quote_path(@quote)
    assert_response :success
    assert_select '.processing-run__form[action=?]', quote_processing_path(@quote)
    assert_select '.processing-run__form input[name="reviewed_version"][value=?]', @quote.review_revision
    assert_select '.processing-run__form input[type="submit"][value="Process RFQ"]'
    assert_includes response.body, "Rules-based parsing with RudCo and metals catalog matching."
    assert_includes response.body, "No AI provider is called."
  end

  test "duplicate posts enqueue one run and active status has refresh but no retry" do
    revision = @quote.review_revision
    assert_enqueued_jobs 1, only: ProcessRfqJob do
      submit_processing(revision)
      assert_redirected_to quote_path(@quote)
      submit_processing(revision)
      assert_redirected_to quote_path(@quote)
    end
    assert_equal 1, ProcessingRun.where(quote: @quote).count
    assert_equal "queued", latest_run.status
    get quote_path(@quote)
    assert_select ".processing-run__status", text: /Queued/
    assert_select '.processing-run a[href=?]', quote_path(@quote), text: "Refresh processing status"
    assert_select ".processing-run__form", count: 0
  end

  test "missing and stale revisions cannot enqueue" do
    [ nil, "stale", { invalid: "revision" } ].each do |revision|
      assert_no_enqueued_jobs do
        assert_no_difference "ProcessingRun.count" do
          submit_processing(revision)
        end
      end
      assert_redirected_to quote_path(@quote)
      follow_redirect!
      assert_select ".flash--alert", count: 1
    end
  end

  test "processing route is scoped to the current browser" do
    other = open_session
    assert_no_enqueued_jobs do
      other.post quote_processing_path(@quote), params: { reviewed_version: @quote.review_revision }
    end
    assert_equal 404, other.response.status
    assert_nil latest_run
  end

  test "actual rules pipeline completes and shows evidence and unpriced lines" do
    perform_enqueued_jobs(only: ProcessRfqJob) { submit_processing }
    assert_equal "succeeded", latest_run.status
    @quote.reload
    assert @quote.quote_lines.any?
    assert @quote.quote_lines.all? { |line| !line.quotable? && line.unit_price.nil? }
    get quote_path(@quote)
    assert_response :success
    assert_select ".processing-run__status", text: /Succeeded/
    assert_select ".processing-evidence", count: 1
    assert_select ".processing-run__form", count: 0
    assert_select ".lines-table tbody tr", minimum: 1
  end

  test "unsupported source shows failure and a revision guarded retry" do
    @quote.update!(source_bytes: "private workbook bytes", original_filename: "rfq.xlsx")
    perform_enqueued_jobs(only: ProcessRfqJob) { submit_processing }
    assert_equal "failed", latest_run.status
    get quote_path(@quote)
    assert_select ".processing-run__status", text: /Failed/
    assert_select ".processing-run__error", text: /Save this Excel file as CSV/
    assert_select '.processing-run__form input[type="submit"][value="Retry processing"]'
    assert_select '.processing-run__form input[name="reviewed_version"][value=?]', @quote.reload.review_revision
    refute_includes response.body, "private workbook bytes"
  end

  test "manual edit during processing produces conflict and preserves edited lines" do
    submit_processing
    run = latest_run
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: QuoteWorkspace::Demo.result)
    line = @quote.quote_lines.first
    line.apply_manual_edit("description" => "Rep-confirmed description")
    ProcessRfqJob.perform_now(run.id)
    assert_equal "conflict", run.reload.status
    assert_equal "Rep-confirmed description", line.reload.description
    get quote_path(@quote)
    assert_select ".processing-run__status", text: /Conflict/
    assert_select ".processing-run__error", text: /rep edits/
    assert_select ".processing-run__form", count: 0
  end

  test "existing lines cannot be destructively reprocessed by direct post" do
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: QuoteWorkspace::Demo.result)
    @quote.approve!
    originals = @quote.quote_lines.map(&:attributes)
    original_quote = @quote.attributes
    assert_no_enqueued_jobs { submit_processing }
    assert_redirected_to quote_path(@quote)
    assert_nil latest_run
    assert_equal originals, @quote.reload.quote_lines.map(&:attributes)
    assert_equal original_quote, @quote.attributes
  end

  test "stale empty run offers safe retry without applying old results" do
    submit_processing
    run = latest_run
    @quote.reload.update!(title: "Updated title")
    ProcessRfqJob.perform_now(run.id)
    assert_equal "stale", run.reload.status
    get quote_path(@quote)
    assert_select ".processing-run__status", text: /Stale/
    assert_select '.processing-run__form input[type="submit"][value="Retry processing"]'
    assert @quote.reload.quote_lines.empty?
  end

  test "run failure and extraction warning strings are escaped" do
    malicious = '<script>alert("warning")</script>'
    submit_processing
    latest_run.update!(status: "failed", error_message: malicious, finished_at: Time.current)
    @quote.reload.assign_processing_evidence(source: { "type" => "pdf", "filename" => malicious }, warnings: [ malicious ]).save!
    get quote_path(@quote)
    assert_select ".processing-run script, .processing-evidence script", count: 0
    assert_select ".processing-run__error", text: malicious
    assert_select ".processing-evidence li", text: malicious
    assert_includes response.body, "&lt;script&gt;"
  end
end
