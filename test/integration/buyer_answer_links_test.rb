require "test_helper"
require "minitest/mock"
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

class BuyerAnswerLinksTest < ActionDispatch::IntegrationTest
  setup do
    @quote = Quote.create!(title: "PRIVATE BUYER QUOTE", buyer_name: "PRIVATE BUYER", source_text: "S-330 steel shot, lb", workspace_token: "answer-link-test")
    result = RfqProcessing.process(content: @quote.source_text, llm: false)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
    @line = @quote.quote_lines.first
    @line.update!(processing: @line.processing.merge("question_choices" => [
      {"id" => "quantity-choice", "field" => "quantity", "value" => 100, "label" => "100 lb"}]))
    @link = QuoteWorkspace::BuyerAnswerLink.for_line(@line).sole
    @token = URI.decode_www_form(URI.parse(@link[:url]).query).to_h.fetch("token")
  end

  test "a public click records the offered answer once without exposing quote details" do
    assert @link[:url].start_with?("http://127.0.0.1:3100/buyer-answer?")
    get buyer_answer_link_path(token: @token), params: {free_text: "99999 lb", choice_id: "forged"}
    assert_response :success
    assert_includes response.body, "Thank you. Your answer is recorded."
    refute_includes response.body, "PRIVATE BUYER"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal BigDecimal("100"), @line.reload.quantity
    assert BuyerAnswerToken.sole.used_at
    before = @line.attributes
    get buyer_answer_link_path(token: @token)
    assert_response :unprocessable_entity
    assert_equal before, @line.reload.attributes
  end

  test "expired and forged signatures cannot record an answer" do
    travel 25.hours do
      get buyer_answer_link_path(token: @token)
      assert_response :unprocessable_entity
    end
    get buyer_answer_link_path(token: @token + "x")
    assert_response :unprocessable_entity
    assert_nil BuyerAnswerToken.sole.used_at
    assert_nil @line.reload.quantity
  end

  test "changed question choice and review invalidate old links without consuming them" do
    @line.update!(clarification_question: "A changed question")
    get buyer_answer_link_path(token: @token)
    assert_response :unprocessable_entity
    assert_nil BuyerAnswerToken.sole.used_at
    assert_nil @line.reload.quantity
  end

  test "changed choice payload is rejected even when the review timestamp has not changed" do
    processing = @line.processing.deep_dup
    processing["question_choices"].first["value"] = 999
    @line.update_columns(processing: processing)
    get buyer_answer_link_path(token: @token)
    assert_response :unprocessable_entity
    assert_nil BuyerAnswerToken.sole.used_at
    assert_nil @line.reload.quantity
  end

  test "two held lines can both be answered using links from the original email" do
    quote = Quote.create!(title: "Two questions", source_text: "S-330 steel shot, lb\nS-390 steel shot, lb", workspace_token: "two-link-test")
    result = RfqProcessing.process(content: quote.source_text, llm: false)
    QuoteWorkspace::ApplyResult.call(quote: quote, result: result)
    assert_equal 2, quote.quote_lines.count
    quote.quote_lines.each do |line|
      line.update!(processing: line.processing.merge("question_choices" => [
        {"id" => "quantity-choice", "field" => "quantity", "value" => 100, "label" => "100 lb"}]))
    end
    message = QuoteWorkspace::EmailPreview.call(quote: quote, kind: "questions", expected_revision: quote.reload.review_revision)
    links = QuoteWorkspace::BuyerAnswerLink.from_message(message, quote: quote)
    assert_equal 2, links.size
    assert_equal ["Line 1: 100 lb", "Line 2: 100 lb"], links.map { |link| link[:label] }
    links.each do |link|
      get link.fetch(:url)
      assert_response :success
    end
    assert_equal [BigDecimal("100"), BigDecimal("100")], quote.quote_lines.reload.map(&:quantity)
    assert_equal 2, BuyerAnswerToken.where(quote: quote).where.not(used_at: nil).count
  end

  test "own line evidence or rep edits invalidate a saved answer link" do
    @line.update_columns(evidence: {"changed" => "source evidence"})
    get buyer_answer_link_path(token: @token)
    assert_response :unprocessable_entity
    assert_nil BuyerAnswerToken.sole.used_at
    assert_nil @line.reload.quantity
  end

  test "an overlapping click has one winner after processing revision is rechecked" do
    original = RfqProcessing::Answers.method(:apply)
    nested = false
    RfqProcessing::Answers.stub(:apply, lambda { |**arguments|
      unless nested
        nested = true
        assert QuoteWorkspace::BuyerAnswerLink.consume!(@token)
      end
      original.call(**arguments)
    }) do
      assert_raises(QuoteWorkspace::BuyerAnswerLink::Invalid) { QuoteWorkspace::BuyerAnswerLink.consume!(@token) }
    end
    assert BuyerAnswerToken.sole.used_at
    assert_equal BigDecimal("100"), @line.reload.quantity
  end

  test "failed answer does not consume the current token" do
    QuoteWorkspace::ApplyBuyerAnswer.stub(:call, ->(**, &) { raise QuoteWorkspace::ApplyBuyerAnswer::Invalid, "private reason" }) do
      get buyer_answer_link_path(token: @token)
      assert_response :unprocessable_entity
      refute_includes response.body, "private reason"
    end
    assert_nil BuyerAnswerToken.sole.used_at
    get buyer_answer_link_path(token: @token)
    assert_response :success
  end

  test "message link extraction reconstructs only signed same-quote links without trusting HTML" do
    mail = Mail.new
    mail.html_part = Mail::Part.new(content_type: "text/html", body: "<script>alert(1)</script><a href='#{@link[:url]}'>Untrusted label</a><a href='https://evil.test/'>Wrong</a>")
    links = QuoteWorkspace::BuyerAnswerLink.from_message(mail, quote: @quote)
    assert_equal [{label: "Line 1: 100 lb", url: buyer_answer_link_path(token: @token)}], links
    other = Quote.create!(title: "Other", source_text: "Other RFQ", workspace_token: "other")
    assert_empty QuoteWorkspace::BuyerAnswerLink.from_message(mail, quote: other)
  end

  test "question mail contains escaped choice anchors and keeps local-only wording" do
    message = QuoteWorkspace::EmailPreview.call(quote: @quote, kind: "questions", expected_revision: @quote.reload.review_revision)
    assert message.html_part
    assert_includes message.text_part.decoded, "No email is sent to the buyer."
    assert_includes message.html_part.decoded, "/buyer-answer?token="
    assert_includes message.text_part.decoded, "/buyer-answer?token="
    refute_includes Nokogiri::HTML.fragment(message.html_part.decoded).text, "/buyer-answer?token="
    assert_equal 1, QuoteWorkspace::BuyerAnswerLink.from_message(message, quote: @quote).size
    links = QuoteWorkspace::BuyerAnswerLink.from_message(message, quote: @quote)
    refute_includes QuoteWorkspace::BuyerAnswerLink.display_body(message.text_part.decoded, links: links), "/buyer-answer?token="
  end
end
