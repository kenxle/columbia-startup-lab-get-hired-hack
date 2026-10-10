require "test_helper"
require "minitest/mock"
require "tmpdir"

class SendApprovedQuoteTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "local-send-test")
    ActionMailer::Base.deliveries.clear
  end

  teardown { ActionMailer::Base.deliveries.clear }

  def send_quote(revision = @quote.reload.review_revision)
    QuoteWorkspace::SendApprovedQuote.call(quote: @quote, expected_revision: revision)
  end

  test "explicit send records one local receipt with immutable approved attachments" do
    @quote.approve!
    revision = @quote.reload.review_revision
    approval = @quote.approved_at
    send_quote(revision)
    assert @quote.reload.sent_locally?
    assert_equal revision, @quote.sent_review_revision
    assert_equal revision, @quote.review_revision
    assert_equal approval, @quote.approved_at
    assert_equal "buyer@example.invalid", @quote.sent_recipient
    assert @quote.sent_at
    message = ActionMailer::Base.deliveries.sole
    assert_equal [@quote.sent_recipient], message.to
    assert_equal @quote.id.to_s, message["X-Quote-Desk-Quote-Id"].value
    assert_equal 2, message.attachments.size
    assert message.attachments.find { |part| part.filename.end_with?(".pdf") }.decoded.start_with?("%PDF")
    assert_includes message.attachments.find { |part| part.filename.end_with?(".csv") }.decoded, '"232.00","4640.00"'
    assert_includes message.text_part.decoded, "No email is sent to the buyer."
    assert_includes message.text_part.decoded, "Approved quote, local preview"
    refute_includes message.text_part.decoded, "Draft, not sent"
    sent_at = @quote.sent_at
    send_quote(revision)
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal sent_at, @quote.reload.sent_at
  end

  test "unapproved and stale revisions never send" do
    assert_raises(QuoteWorkspace::EmailPreview::Incomplete, QuoteWorkspace::FinalQuote::NotApproved) { send_quote }
    @quote.approve!
    version = @quote.reload.review_revision
    @quote.quote_lines.first.apply_manual_edit("notes" => "Later edit")
    assert_raises(Quote::StaleReview) { send_quote(version) }
    assert_empty ActionMailer::Base.deliveries
    assert_nil @quote.reload.sent_at
  end

  test "changed sent revision requires approval and a new explicit send" do
    @quote.approve!
    send_quote
    @quote.quote_lines.first.apply_manual_edit("unit_price" => "300")
    refute @quote.reload.sent?
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { send_quote }
    @quote.approve!
    send_quote
    assert @quote.reload.sent_locally?
    assert_equal 2, ActionMailer::Base.deliveries.size
    assert_includes ActionMailer::Base.deliveries.last.attachments.find { |part| part.filename.end_with?(".csv") }.decoded, '"300.00","6000.00"'
  end

  test "transport failure never records sent metadata or leaks error details" do
    @quote.approve!
    delivery = Object.new
    delivery.define_singleton_method(:deliver_now) { raise IOError, "PRIVATE transport detail" }
    QuoteMailer.stub(:local_preview, ->(**) { delivery }) do
      error = assert_raises(QuoteWorkspace::SendApprovedQuote::Failed) { send_quote }
      refute_includes error.message, "PRIVATE"
    end
    assert_nil @quote.reload.sent_at
    assert @quote.approved?
  end

  test "production smtp disabled deliveries and suppressed failures cannot record sends" do
    @quote.approve!
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_raises(QuoteWorkspace::EmailPreview::Unavailable) { send_quote }
    end
    QuoteMailer.stub(:delivery_method, :smtp) do
      assert_raises(QuoteWorkspace::EmailPreview::Unavailable) { send_quote }
    end
    QuoteMailer.stub(:perform_deliveries, false) do
      assert_raises(QuoteWorkspace::EmailPreview::Unavailable) { send_quote }
    end
    QuoteMailer.stub(:raise_delivery_errors, false) do
      assert_raises(QuoteWorkspace::EmailPreview::Unavailable) { send_quote }
    end
    assert_empty ActionMailer::Base.deliveries
    assert_nil @quote.reload.sent_at
  end

  test "expired pricing blocks local send even with a saved approval" do
    @quote.approve!
    line = @quote.quote_lines.first
    line.update_columns(processing: { "distributor_pricing" => { "valid_until" => 1.hour.ago.iso8601 } })
    assert_raises(QuoteWorkspace::FinalQuote::NotApproved) { send_quote }
    assert_empty ActionMailer::Base.deliveries
    assert_nil @quote.reload.sent_at
  end

  test "silent development transport writes the attached email and returns its inbox receipt without launching a browser" do
    require Rails.root.join("lib/quote_workspace/silent_letter_opener")
    @quote.approve!
    original_methods = QuoteMailer.delivery_methods
    Dir.mktmpdir("quote-send-transport") do |directory|
      QuoteMailer.add_delivery_method :silent_letter_opener, QuoteWorkspace::SilentLetterOpener, location: directory
      Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
        QuoteMailer.stub(:delivery_method, :silent_letter_opener) do
          Launchy.stub(:open, ->(*) { flunk "Sending a local quote must not open a browser" }) do
            id = send_quote
            assert_match LocalPreviewsController::UUID, id
            assert_equal id, @quote.reload.sent_preview_id
            stored = Mail.read(File.join(directory, id, "message.eml"))
            assert_equal @quote.id.to_s, stored["X-Quote-Desk-Quote-Id"].value
            assert_equal ["application/pdf", "text/csv"], stored.attachments.map(&:mime_type).sort
            assert_equal ["buyer@example.invalid"], stored.to
            assert_equal id, send_quote
            assert_equal 1, Dir.glob(File.join(directory, "*", "message.eml")).size
          end
        end
      end
    end
  ensure
    QuoteMailer.delivery_methods = original_methods if original_methods
  end
end
