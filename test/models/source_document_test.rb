require "test_helper"
require "prawn"

class SourceDocumentTest < ActiveSupport::TestCase
  def document(**attributes)
    quote = Quote.new(title: "Original", workspace_token: "source-doc", **attributes)
    QuoteWorkspace::SourceDocument.new(quote).call
  end

  test "pasted email and raw CSV preserve headers body blank rows and attachments" do
    email = "From: Buyer\nPlease quote attached.\n\nDFARS on all lines.\nThanks"
    csv = "Description,Quantity\n\"S-330, steel shot\",100\n\nFooter,terms\n"
    result = document(source_text: email, source_bytes: csv, original_filename: "RFQ.csv")
    assert_equal [email, csv], result.sections.map { |section| section[:text] }
    assert_empty result.warnings
  end

  test "PDF display includes header footer and non-item text" do
    bytes = Prawn::Document.new { text "Purchasing department"; text "S-330 steel shot, 100 lb"; text "Please deliver to dock three" }.render
    result = document(source_bytes: bytes, original_filename: "RFQ.pdf")
    text = result.sections.sole[:text]
    ["Purchasing department", "S-330 steel shot", "Please deliver to dock three"].each { |phrase| assert_includes text, phrase }
    assert_empty result.warnings
  end

  test "unreadable unsupported or invalid encoded attachments are warned never reconstructed" do
    [["%PDF-broken", "bad.pdf"], ["binary", "book.xlsx"], ["\xFF".b, "bad.csv"]].each do |bytes, name|
      result = document(source_text: "Original body", source_bytes: bytes, original_filename: name)
      assert_equal ["Original body"], result.sections.map { |section| section[:text] }
      assert result.warnings.any?
      assert_match(/Download the original/, result.warnings.join)
    end
  end

  test "one line source is not duplicated" do
    result = document(source_text: "S-330 steel shot, 100 lb")
    assert_equal 1, result.sections.size
    assert_equal "S-330 steel shot, 100 lb", result.sections.first[:text]
  end
end
