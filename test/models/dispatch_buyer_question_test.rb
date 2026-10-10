require "test_helper"
require "minitest/mock"

class DispatchBuyerQuestionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "question-preview")
    @line = @quote.quote_lines.find_by!(state: "needs_buyer")
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear
  end

  def dispatch(line = @line, fingerprint: line.question_delivery_fingerprint)
    DispatchBuyerQuestionJob.perform_now(line.id, fingerprint)
  end

  test "successful local preview is audited once without changing quote content or approval" do
    @quote.approve!
    quote_before = @quote.attributes
    line_before = @line.attributes
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      dispatch
      dispatch
    end
    delivery = @line.current_question_delivery
    assert delivery
    assert_equal "previewed", delivery.status
    assert_equal "local_preview", delivery.channel
    assert_equal "buyer@example.invalid", delivery.recipient
    assert_equal @quote.buyer_name, delivery.buyer_name
    assert_equal @line.clarification_question, delivery.question_text
    assert_equal @line.position, delivery.line_position
    assert_equal "Waiting on buyer", @line.status_label
    assert_equal ["buyer@example.invalid"], ActionMailer::Base.deliveries.last.to
    assert_includes ActionMailer::Base.deliveries.last.body.decoded, "No email has been sent to the buyer"
    assert_equal quote_before, @quote.reload.attributes
    assert_equal line_before, @line.reload.attributes
    assert_equal 1, @line.buyer_question_deliveries.count
  end

  test "changed question or specs invalidate old preview and stale jobs do nothing" do
    old = @line.question_delivery_fingerprint
    dispatch
    @line.update!(clarification_question: "Please confirm the material grade.")
    assert_nil @line.current_question_delivery
    assert_equal "Question to send", @line.status_label
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      dispatch(fingerprint: old)
    end
    dispatch
    assert @line.current_question_delivery
    @line.update!(spec: @line.spec.merge("grade" => "A36"))
    assert_nil @line.current_question_delivery
  end

  test "failed and pending attempts never mean waiting and errors remain private" do
    QuoteMailer.stub(:local_preview, ->(**) { raise "private transport details" }) { dispatch }
    delivery = @line.buyer_question_deliveries.sole
    assert_equal "failed", delivery.status
    assert_nil delivery.previewed_at
    refute_includes delivery.error_message, "private"
    assert_nil @line.current_question_delivery
    assert_equal "Question to send", @line.status_label
    delivery.update!(status: "pending")
    assert_nil @line.current_question_delivery
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      dispatch
    end
  end

  test "a failed line does not prevent another line preview" do
    QuoteMailer.stub(:local_preview, ->(**) { raise "unavailable" }) { dispatch }
    other = @quote.quote_lines.find_by!(state: "no_match")
    dispatch(other)
    assert other.current_question_delivery
    assert_equal "No match", other.status_label
  end

  test "ready lines and missing questions never queue or preview" do
    ready = @quote.quote_lines.find_by!(state: "ready")
    assert_no_enqueued_jobs only: DispatchBuyerQuestionJob do
      ready.update!(notes: "Internal note")
      @line.update!(clarification_question: nil)
    end
    assert_no_difference "BuyerQuestionDelivery.count" do
      dispatch(ready)
      dispatch
    end
  end

  test "semantic edits queue after commit but notes and GET style reads do not" do
    assert_enqueued_jobs 1, only: DispatchBuyerQuestionJob do
      @line.update!(clarification_question: "Which grade is required?")
    end
    assert_no_enqueued_jobs only: DispatchBuyerQuestionJob do
      @line.update!(notes: "Internal only")
      @line.status_label
      @line.current_question_delivery
    end
    assert_enqueued_jobs 2, only: DispatchBuyerQuestionJob do
      QuoteWorkspace::Demo.create!(workspace_token: "another-preview")
    end
  end

  test "production and unsafe transport are disabled" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_no_enqueued_jobs only: DispatchBuyerQuestionJob do
        @line.update!(clarification_question: "Confirm finish?")
      end
      assert_no_difference "BuyerQuestionDelivery.count" do
        dispatch
      end
    end
    QuoteMailer.stub(:delivery_method, :smtp) { dispatch }
    assert_equal "failed", @line.buyer_question_deliveries.sole.status
    assert_empty ActionMailer::Base.deliveries
  end

  test "audit survives line replacement and stale deleted-line jobs are harmless" do
    dispatch
    delivery = @line.current_question_delivery
    fingerprint = @line.question_delivery_fingerprint
    @quote.quote_lines.delete_all
    assert_nil delivery.reload.quote_line_id
    assert_equal @line.position, delivery.line_position
    assert_equal @line.clarification_question, delivery.question_text
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      DispatchBuyerQuestionJob.perform_now(@line.id, fingerprint)
    end
  end
end
