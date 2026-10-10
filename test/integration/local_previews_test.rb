require "test_helper"
require "fileutils"

class LocalPreviewsTest < ActionDispatch::IntegrationTest
  setup do
    post demo_quotes_path
    @quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    @ids = []
  end

  teardown do
    @ids.each { |id| FileUtils.rm_rf(Rails.root.join("tmp/letter_opener", id)) }
  end

  def artifact(quote_id:, subject: "Local preview")
    id = SecureRandom.uuid
    @ids << id
    directory = Rails.root.join("tmp/letter_opener", id)
    FileUtils.mkdir_p(directory)
    mail = Mail.new(from: "desk@example.invalid", to: "buyer@example.invalid", subject: subject)
    mail["X-Quote-Desk-Quote-Id"] = quote_id.to_s
    mail.text_part = Mail::Part.new(body: "<script>buyer text</script>")
    mail.attachments["quote.txt"] = "Attachment contents"
    File.binwrite(directory.join("message.eml"), mail.encoded)
    id
  end

  test "inbox scopes messages to the quote escapes body and downloads parsed attachments" do
    id = artifact(quote_id: @quote.id, subject: "My saved question")
    other = artifact(quote_id: @quote.id + 1000, subject: "Other workspace message")
    get quote_local_previews_path(@quote)
    assert_response :success
    assert_includes response.body, "My saved question"
    refute_includes response.body, "Other workspace message"
    get quote_local_preview_path(@quote, id)
    assert_response :success
    assert_includes response.body, "&lt;script&gt;buyer text&lt;/script&gt;"
    refute_includes response.body, "<script>buyer text</script>"
    get attachment_quote_local_preview_path(@quote, id, index: 0)
    assert_equal "Attachment contents", response.body
    get download_quote_local_preview_path(@quote, id)
    assert_response :success
    assert_equal "My saved question", Mail.read_from_string(response.body).subject
    get quote_local_preview_path(@quote, other)
    assert_response :not_found
    get attachment_quote_local_preview_path(@quote, id, index: -1)
    assert_response :not_found
    session = open_session
    session.get quote_local_preview_path(@quote, id)
    assert_equal 404, session.response.status
  end

  test "malformed ids and symbolic links never disclose files" do
    id = artifact(quote_id: @quote.id)
    get quote_local_preview_path(@quote, "not-a-uuid")
    assert_response :not_found
    path = Rails.root.join("tmp/letter_opener", id, "message.eml")
    stored = path.dirname.join("hidden.eml")
    File.rename(path, stored)
    File.symlink(stored, path)
    get quote_local_preview_path(@quote, id)
    assert_response :not_found
  end
end
