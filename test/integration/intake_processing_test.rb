require "test_helper"
require "minitest/mock"
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

class IntakeProcessingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def save_rfq(attributes = {})
    post quotes_path, params: { quote: {
      title: "Shot request", buyer_name: "Northline Fabrication", source_text: "S-330 steel shot, 100 lb"
    }.merge(attributes) }
    Quote.find(response.location[%r{/quotes/(\d+)}, 1])
  end

  test "saving an RFQ queues one job without running the parser in the request" do
    quote = nil
    RfqProcessing.stub(:process, ->(**) { flunk "Parser must not run during intake" }) do
      assert_enqueued_jobs 1, only: ProcessRfqJob do
        quote = save_rfq
      end
    end
    assert_redirected_to quote_path(quote)
    assert quote.quote_lines.empty?
    run = quote.processing_runs.sole
    assert_equal "queued", run.status
    assert_equal "S-330 steel shot, 100 lb", run.source_content
    assert_equal quote.review_revision, run.source_revision
    follow_redirect!
    assert_select ".flash--notice", text: /Processing is queued/
    assert_select ".processing-run__status", text: /Queued/
    assert_select ".processing-run__form", count: 0
  end

  test "saved email automatically processes shot priced per pound with traceable source" do
    quote = save_rfq
    perform_enqueued_jobs only: ProcessRfqJob
    quote.reload
    assert_equal "succeeded", quote.processing_runs.sole.status
    line = quote.quote_lines.sole
    assert line.quotable?, line.attributes.inspect
    assert_equal BigDecimal("100"), line.quantity
    assert_equal "lb", line.quantity_unit
    assert_equal "RC-STEELSHOT-S330", line.catalog_sku
    assert line.unit_price.positive?
    assert line.price_source.present?
    assert_equal "email", quote.processing_source["type"]
    assert line.evidence.present?
    assert quote.sample_data?
    refute quote.approved?
    get quote_path(quote)
    assert_select ".processing-run__status", text: /Succeeded/
    assert_select ".processing-evidence", count: 1
    assert_select ".lines-table tbody tr", count: 1
  end

  test "unsupported saved spreadsheet fails recoverably without inventing quote lines" do
    upload = Rack::Test::UploadedFile.new(StringIO.new("private workbook bytes"),
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", true, original_filename: "request.xlsx")
    quote = save_rfq(source_text: "", source_file: upload)
    perform_enqueued_jobs only: ProcessRfqJob
    assert_equal "failed", quote.processing_runs.sole.status
    assert_empty quote.reload.quote_lines
    assert_equal "private workbook bytes", quote.source_bytes
    get quote_path(quote)
    assert_select ".processing-run__error", text: /save.*CSV/i
    assert_select '.processing-run__form input[value="Retry processing"]'
    refute_includes response.body, "private workbook bytes"
  end

  test "unpriced unsupported sale units stay held after automatic processing" do
    quote = save_rfq(source_text: "S-330 steel shot, 2 bags")
    perform_enqueued_jobs only: ProcessRfqJob
    assert_equal "succeeded", quote.processing_runs.sole.status
    line = quote.reload.quote_lines.sole
    refute line.quotable?
    assert_nil line.unit_price
    assert line.clarification_question.present?
    assert_equal BigDecimal("0"), quote.subtotal
  end

  test "queue adapter failure leaves saved RFQ and explicit retry action" do
    quote = nil
    ProcessRfqJob.stub(:perform_later, false) { quote = save_rfq }
    assert_redirected_to quote_path(quote)
    assert_equal "failed", quote.processing_runs.sole.status
    assert_empty quote.quote_lines
    follow_redirect!
    assert_select ".flash--alert", text: /RFQ saved.*could not be queued/
    assert_select '.processing-run__form input[value="Retry processing"]'
  end

  test "unexpected enqueue failure preserves intake without exposing internal errors" do
    quote = nil
    QuoteWorkspace::ProcessRfq.stub(:enqueue, ->(**) { raise "SECRET-QUEUE-FAILURE" }) { quote = save_rfq }
    assert_redirected_to quote_path(quote)
    assert_empty quote.processing_runs
    follow_redirect!
    assert_select ".flash--alert", text: /RFQ saved, but processing could not be queued/
    assert_select '.processing-run__form input[value="Process RFQ"]'
    refute_includes response.body, "SECRET-QUEUE-FAILURE"
  end

  test "late intake job preserves intervening reviewed lines and rep edits" do
    quote = save_rfq
    QuoteWorkspace::ApplyResult.call(quote: quote, result: QuoteWorkspace::Demo.result)
    quote.quote_lines.first.apply_manual_edit("description" => "Rep reviewed specification")
    originals = quote.quote_lines.reload.map(&:attributes)
    perform_enqueued_jobs only: ProcessRfqJob
    assert_equal "conflict", quote.processing_runs.sole.status
    assert_equal originals, quote.reload.quote_lines.map(&:attributes)
  end

  test "invalid intake never queues processing" do
    assert_no_enqueued_jobs do
      assert_no_difference "ProcessingRun.count" do
        post quotes_path, params: { quote: { title: "", source_text: "" } }
      end
    end
    assert_response :unprocessable_content
  end
end
