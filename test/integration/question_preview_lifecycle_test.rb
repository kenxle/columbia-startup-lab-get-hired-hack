require "test_helper"
require "minitest/mock"

class QuestionPreviewLifecycleTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "GET seeding refresh and explicit demo population never queue question previews" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      assert_no_enqueued_jobs only: DispatchBuyerQuestionJob do
        get quotes_path
        assert_response :success
        assert_equal QuoteWorkspace::DemoWorkspace::SIZE, Quote.count
        quote = Quote.first
        get quote_path(quote)
        assert_response :success
        get quote_buyer_questions_path(quote)
        assert_response :success
        get quotes_path
        assert_response :success
        QuoteWorkspace::DemoWorkspace.populate!(workspace_token: quote.workspace_token)
        Quote.last.destroy!
        QuoteWorkspace::DemoWorkspace.populate!(workspace_token: quote.workspace_token)
      end
    end
    assert_equal 0, BuyerQuestionDelivery.count
  end

  test "real intake processing queues its held question automatically and reads do not repeat it" do
    assert_no_enqueued_jobs only: DispatchBuyerQuestionJob do
      post quotes_path, params: { quote: { title: "Bag quantity to confirm", buyer_name: "Northline Fabrication",
        source_text: "S-330 steel shot, 2 bags" } }
    end
    quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    assert_enqueued_jobs 1, only: DispatchBuyerQuestionJob do
      perform_enqueued_jobs only: ProcessRfqJob
    end
    assert_equal "succeeded", quote.reload.processing_runs.sole.status
    line = quote.quote_lines.sole
    assert line.question_preview_eligible?

    assert_no_enqueued_jobs only: DispatchBuyerQuestionJob do
      get quote_path(quote)
      assert_response :success
      get quote_buyer_questions_path(quote)
      assert_response :success
      get quotes_path
      assert_response :success
    end
    job = enqueued_jobs.find { |entry| entry[:job] == DispatchBuyerQuestionJob }
    assert_equal [line.id, line.question_delivery_fingerprint], job.fetch(:args)
  end
end
