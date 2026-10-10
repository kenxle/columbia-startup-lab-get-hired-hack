# Standalone transport tests: no Rails boot, database or provider is required.
require "bundler/setup"
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "mail"
require_relative "../../lib/quote_workspace/silent_letter_opener"

class SilentLetterOpenerTest < Minitest::Test
  def test_writes_readable_artifacts_and_attachments_without_launching_a_browser
    Dir.mktmpdir do |directory|
      mail = Mail.new(from: "quote-desk@example.invalid", to: "buyer@example.invalid",
        subject: "Local question preview")
      mail.text_part = Mail::Part.new(body: "Local preview only. Which grade is required?")
      mail.attachments["quote.txt"] = "Local attachment"
      delivery = QuoteWorkspace::SilentLetterOpener.new(location: directory, message_template: "default")
      Launchy.stub(:open, ->(*) { flunk "Delivery must never open a browser" }) do
        2.times { delivery.deliver!(mail) }
      end
      assert_equal 2, Dir.children(directory).length
      pages = Dir.glob(File.join(directory, "*", "plain.html"))
      assert_equal 2, pages.length
      pages.each do |page|
        assert_includes File.read(page), "Which grade is required?"
        assert_equal "Local attachment", File.read(File.join(File.dirname(page), "attachments", "quote.txt"))
      end
      assert File.exist?(Array(mail["location_plain"]).last.value)
      id = Array(mail["X-Local-Preview-ID"]).last.value
      assert_match(/\A[0-9a-f-]{36}\z/, id)
      stored = Mail.read(File.join(directory, id, "message.eml"))
      assert_equal ["buyer@example.invalid"], stored.to
      assert_equal "Local attachment", stored.attachments.first.decoded
    end
  end

  def test_refuses_real_recipients_including_cc_and_bcc_before_writing
    Dir.mktmpdir do |directory|
      delivery = QuoteWorkspace::SilentLetterOpener.new(location: directory, message_template: "default")
      [:to, :cc, :bcc].each do |field|
        mail = Mail.new(from: "quote-desk@example.invalid", to: "buyer@example.invalid", body: "Local only")
        mail[field] = "person@example.com"
        assert_raises(ArgumentError) { delivery.deliver!(mail) }
      end
      assert_empty Dir.children(directory)
    end
  end
end
