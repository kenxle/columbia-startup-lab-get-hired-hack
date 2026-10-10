require "test_helper"

class QuoteDeadlineTest < ActiveSupport::TestCase
  test "deadline is exactly 24 hours after receipt across daylight saving" do
    quote = Quote.new(created_at: Time.iso8601("2026-11-01T00:30:00-04:00"))
    assert_equal quote.created_at + 86_400, quote.due_at
  end

  test "approval does not imply delivery and editing a sent revision needs another send" do
    quote = QuoteWorkspace::Demo.create!(workspace_token: "deadline")
    quote.approve!
    refute quote.sent?
    quote.update_columns(sent_at: Time.current, sent_review_revision: quote.review_revision)
    assert quote.reload.sent?
    quote.quote_lines.first.apply_manual_edit("notes" => "Revised after delivery")
    refute quote.reload.sent?
    assert quote.sent_at.present?
    assert quote.valid?
  end

  test "sent time requires a revision and cannot precede receipt" do
    quote = QuoteWorkspace::Demo.create!(workspace_token: "deadline")
    quote.sent_at = quote.created_at - 1.minute
    refute quote.valid?
    assert quote.errors[:sent_at].any?
    assert quote.errors[:sent_review_revision].any?
  end
end
