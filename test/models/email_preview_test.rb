require "test_helper"
require "minitest/mock"

class EmailPreviewTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "email-preview-test")
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    ActionMailer::Base.deliveries.clear
  end

  def preview(kind = "quote", revision: @quote.reload.review_revision)
    QuoteWorkspace::EmailPreview.call(quote: @quote, kind: kind, expected_revision: revision)
  end

  test "approved quote opens safe demo message with PDF and CSV attachments" do
    @quote.approve!
    message = preview

    assert_equal 1, ActionMailer::Base.deliveries.length
    assert_equal ["quote-desk@example.invalid"], message.from
    assert_equal ["buyer@example.invalid"], message.to
    assert_kind_of Mail::TestMailer, message.delivery_method
    assert_match(/Local preview/, message.subject)
    assert_match(/Local preview/, message.text_part.decoded)
    assert_match(/No email/, message.text_part.decoded)
    assert_equal 2, message.attachments.length
    pdf = message.attachments.find { |attachment| attachment.filename.end_with?(".pdf") }
    csv = message.attachments.find { |attachment| attachment.filename.end_with?(".csv") }
    assert pdf.decoded.start_with?("%PDF")
    assert_includes csv.decoded, '"232.00","4640.00"'
    refute_includes csv.decoded, "SAMPLE DATA"
    assert_nil message.in_reply_to
  end

  test "question preview uses existing questions without quote approval or invented choices" do
    message = preview("questions")
    assert_empty message.attachments
    assert_includes message.body.decoded, @quote.quote_lines.second.clarification_question
    assert_includes message.body.decoded, @quote.quote_lines.third.clarification_question
    refute @quote.reload.approved?
    assert_equal 1, ActionMailer::Base.deliveries.length
  end

  test "unapproved quote and incomplete questions cannot create mail" do
    assert_raises(QuoteWorkspace::EmailPreview::Incomplete) { preview }
    @quote.quote_lines.second.update!(clarification_question: nil)
    assert_raises(QuoteWorkspace::EmailPreview::Incomplete) { preview("questions") }
    assert_empty ActionMailer::Base.deliveries
  end

  test "expected revision is required and rechecked after an edit" do
    @quote.approve!
    revision = @quote.review_revision
    @quote.quote_lines.first.apply_manual_edit("notes" => "A later edit")
    assert_raises(Quote::StaleReview) { preview(revision: revision) }
    assert_raises(Quote::StaleReview) { preview("questions", revision: nil) }
    assert_empty ActionMailer::Base.deliveries
  end

  test "unsafe configured transport is rejected by service and mailer" do
    QuoteMailer.stub(:delivery_method, :smtp) do
      assert_raises(QuoteWorkspace::EmailPreview::Unavailable) { preview("questions") }
      assert_raises(QuoteWorkspace::EmailPreview::Unavailable) do
        QuoteMailer.local_preview(snapshot: {subject: "Demo", body: "Demo", attachments: []}).deliver_now
      end
    end
    assert_empty ActionMailer::Base.deliveries
  end

  test "production cannot create previews even with test configured" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_raises(QuoteWorkspace::EmailPreview::Unavailable) { preview("questions") }
    end
    assert_empty ActionMailer::Base.deliveries
  end

  test "mailer removes subject newlines" do
    message = QuoteMailer.local_preview(snapshot: {
      subject: "Preview\r\nBcc: nobody@example.invalid", body: "Local demo", attachments: []
    }).deliver_now
    refute_match(/[\r\n]/, message.subject)
    assert_nil message.bcc
  end

  test "snapshot freezes rendered artifacts before handing them to the mailer" do
    @quote.approve!
    captured = nil
    delivery = Object.new
    delivery.define_singleton_method(:deliver_now) { :preview_created }
    QuoteMailer.stub(:local_preview, ->(snapshot:) { captured = snapshot; delivery }) do
      assert_equal :preview_created, preview
    end
    assert captured.frozen?
    assert captured[:body].frozen?
    assert captured[:attachments].all? { |entry| entry.frozen? && entry.values.all?(&:frozen?) }
    @quote.quote_lines.first.apply_manual_edit("unit_price" => "300")
    csv = captured[:attachments].find { |entry| entry[:content_type] == "text/csv" }
    assert_includes csv[:content], '"232.00","4640.00"'
    refute_includes csv[:content], '"300.00","6000.00"'
  end
end
