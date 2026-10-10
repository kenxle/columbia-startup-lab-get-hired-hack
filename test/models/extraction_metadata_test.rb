require "test_helper"

class ExtractionMetadataTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "extraction-metadata")
    @source = { "type" => "pdf", "filename" => "request.pdf", "pages" => 2, "rows" => nil }
  end

  def apply(result)
    QuoteWorkspace::ApplyResult.call(quote: @quote, result: result)
  end

  test "source warnings lines and revision persist together and invalidate approval" do
    @quote.approve!
    result = QuoteWorkspace::Demo.result.merge("source" => @source, "warnings" => [ "Page 2 has no text." ], "revision" => { "id" => "extraction-2" })
    apply(result)
    assert_equal @source, @quote.reload.processing_source
    assert_equal [ "Page 2 has no text." ], @quote.processing_warnings
    assert_equal "extraction-2", @quote.processing_revision["id"]
    assert_equal 3, @quote.quote_lines.count
    refute @quote.approved?
  end

  test "legacy omitted and null evidence clear previously stored evidence" do
    [ {}, { "source" => nil, "warnings" => nil } ].each do |fields|
      @quote.assign_processing_evidence(source: @source, warnings: [ "Old warning" ]).save!
      apply(QuoteWorkspace::Demo.result.merge(fields))
      assert_nil @quote.reload.processing_source
      assert_equal [], @quote.processing_warnings
    end
  end

  test "every supported source type and zero page or row count is accepted" do
    Quote::PROCESSING_SOURCE_TYPES.each do |type|
      source = { type: type, filename: nil, pages: 0, rows: 0 }
      @quote.assign_processing_evidence(source: source, warnings: nil)
      assert_equal source.stringify_keys, @quote.processing_source
      assert_empty @quote.processing_warnings
      assert @quote.valid?, @quote.errors.full_messages.join(", ")
    end
  end

  test "unknown keys duplicate keys malformed source and unsupported types are rejected" do
    [ "pdf", {}, { "type" => "exe" }, { "type" => :pdf }, { "type" => "pdf", "extra" => "private" },
      { "type" => "pdf", type: "pdf" }, { "type" => "pdf", "pages" => -1 }, { "type" => "pdf", "rows" => 1.5 },
      { "type" => "pdf", "pages" => "2" }, { "type" => "pdf", "filename" => "x" * 256 },
      { "type" => "pdf", "filename" => 12 } ].each do |source|
      assert_raises(Quote::InvalidProcessingEvidence) { @quote.assign_processing_evidence(source: source, warnings: []) }
    end
  end

  test "warnings have bounded count type length encoding and total byte size" do
    [ "warning", [ {} ], Array.new(101, "warning"), [ "x" * 1001 ], [ "\xFF".b.force_encoding("UTF-8") ],
      Array.new(20, "é" * 1000) ].each do |warnings|
      assert_raises(Quote::InvalidProcessingEvidence) { @quote.assign_processing_evidence(source: @source, warnings: warnings) }
    end
    assert @quote.assign_processing_evidence(source: @source, warnings: Array.new(100, "Short warning"))
  end

  test "cyclic metadata is rejected before result deep conversion" do
    source = { "type" => "pdf" }
    source["filename"] = source
    warnings = []
    warnings << warnings
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) do
      apply(QuoteWorkspace::Demo.result.merge("source" => source, "warnings" => warnings))
    end
  end

  test "invalid evidence leaves original lines approval revision and source unchanged" do
    @quote.assign_processing_evidence(source: @source, warnings: [ "Existing warning" ]).save!
    @quote.approve!
    before_quote = @quote.attributes
    before_lines = @quote.quote_lines.map(&:attributes)
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) do
      apply(QuoteWorkspace::Demo.result.merge("source" => @source.merge("pages" => -2), "warnings" => []))
    end
    assert_equal before_quote, @quote.reload.attributes
    assert_equal before_lines, @quote.quote_lines.map(&:attributes)
  end

  test "line validation failure rolls back new extraction evidence and replacement" do
    @quote.assign_processing_evidence(source: @source, warnings: [ "Existing warning" ]).save!
    @quote.approve!
    before_quote = @quote.attributes
    before_lines = @quote.quote_lines.map(&:attributes)
    result = QuoteWorkspace::Demo.result.merge("source" => { "type" => "csv", "rows" => 5 }, "warnings" => [ "New warning" ])
    result["lines"].last["description"] = "x" * 501
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) { apply(result) }
    assert_equal before_quote, @quote.reload.attributes
    assert_equal before_lines, @quote.quote_lines.map(&:attributes)
  end

  test "failure evidence assignment does not save or replace lines and can be persisted explicitly" do
    @quote.approve!
    original = @quote.attributes
    line_ids = @quote.quote_lines.pluck(:id)
    assert_same @quote, @quote.assign_processing_evidence(source: @source, warnings: [ "No item lines found" ])
    assert_equal original, Quote.find(@quote.id).attributes
    @quote.save!
    assert_equal [ "No item lines found" ], @quote.reload.processing_warnings
    assert_equal line_ids, @quote.quote_lines.pluck(:id)
    assert @quote.approved?
    assert_equal original["source_text"], @quote.source_text
    assert_nil @quote.source_bytes
  end

  test "invalid failure evidence does not partially assign valid source" do
    assert_raises(Quote::InvalidProcessingEvidence) { @quote.assign_processing_evidence(source: @source, warnings: [ 123 ]) }
    assert_nil @quote.processing_source
  end

  test "model validation also rejects bypassing the assignment helper" do
    @quote.processing_source = { "type" => "unknown" }
    @quote.processing_warnings = "not an array"
    refute @quote.valid?
    assert @quote.errors.full_messages.any? { |message| message.include?("Extraction metadata") }
  end

  test "zero-line result remains rejected without overwriting existing quote" do
    @quote.approve!
    before_quote = @quote.attributes
    assert_raises(QuoteWorkspace::ApplyResult::InvalidResult) do
      apply(QuoteWorkspace::Demo.result.merge("lines" => [], "source" => @source, "warnings" => [ "No lines found" ]))
    end
    assert_equal before_quote, @quote.reload.attributes
  end

  test "internal evidence partial escapes filenames and warnings and displays zero counts" do
    malicious = '<script>alert("rfq")</script>'
    @quote.assign_processing_evidence(source: { "type" => "pdf", "filename" => malicious, "pages" => 0 }, warnings: [ malicious ])
    html = ApplicationController.render(partial: "quotes/processing_evidence", locals: { quote: @quote })
    assert_includes html, "&lt;script&gt;"
    refute_includes html, "<script>"
    assert_includes html, "<dt>Pages</dt><dd>0</dd>"
    assert_includes html, "excluded from buyer exports"
  end

  test "extraction metadata stays out of all buyer exports" do
    @quote.assign_processing_evidence(source: { "type" => "pdf", "filename" => "PRIVATE-EXTRACTION-FILE" }, warnings: [ "PRIVATE-EXTRACTION-WARNING" ]).save!
    @quote.approve!
    values = [ QuoteWorkspace::CsvExport.new(@quote).to_csv, QuoteWorkspace::FinalQuote.new(@quote).body,
      QuoteWorkspace::BuyerQuestionDraft.new(@quote).body ]
    QuoteWorkspace::FinalQuote.new(@quote).with_snapshot { |data| values << data.to_json }
    values.each do |value|
      refute_includes value, "PRIVATE-EXTRACTION-FILE"
      refute_includes value, "PRIVATE-EXTRACTION-WARNING"
    end
  end
end
