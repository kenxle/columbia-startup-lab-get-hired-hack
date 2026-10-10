# Run through Rails runner in RAILS_ENV=test. All writes roll back. No network calls.
require Rails.root.join("tools/rfq_processing/lib/rfq_processing").to_s

failures = []
normalized = {}
ActiveRecord::Base.transaction do
  catalog = CatalogMatch::Catalog.new(%w[rudco metals])
  matcher = QuoteWorkspace::ProcessRfq::IntakeMatcher.new(client: nil, catalog: catalog, service: CatalogMatch::Matcher)
  pipeline = RfqProcessing::Pipeline.new(matcher: matcher, llm: false)
  { "email.txt" => "email", "northline_rfq_2026-1010.pdf" => "pdf", "northline_rfq_2026-1010.csv" => "csv" }.each do |file, type|
    begin
      check = ->(condition, message) { failures << "#{file}: #{message}" unless condition }
      before = failures.size
      content = File.binread(Rails.root.join("docs/product/demo_rfq", file))
      result = pipeline.process(content: content, type: type, filename: file, sample_data: true)
      lines = result["lines"]
      check.call(lines.size == 8, "expected eight items, got #{lines.size}; warnings: #{result['warnings'].inspect}")
      next unless lines.size == 8

      { 0 => { "thickness" => 0.0625, "width" => 48, "length" => 96, "quantity" => 20 },
        2 => { "thickness" => 0.375, "width" => 60, "length" => 120, "quantity" => 2 },
        6 => { "thickness" => 0.5, "quantity" => 3 } }.each do |index, expected|
        expected.each do |key, value|
          actual = key == "quantity" ? lines[index][key] : lines[index].dig("spec", key)
          check.call(actual == value, "line #{index + 1} #{key}: expected #{value.inspect}, got #{actual.inspect}")
        end
      end
      check.call(lines[2].dig("spec", "grade") == "316L", "line 3 expected grade 316L, got #{lines[2].dig('spec', 'grade').inspect}")
      check.call(lines[2].dig("spec", "standard").to_s.include?("SA-240"), "line 3 expected SA-240 standard, got #{lines[2].dig('spec', 'standard').inspect}")
      check.call(lines[3].values_at("quantity", "quantity_unit") == [2000, "lb"], "packaging replaced demand: #{lines[3].values_at('quantity', 'quantity_unit').inspect}")
      check.call(lines[0]["unit_price"].nil?, "fabricated sheet price")
      check.call(%w[needs_buyer no_match].include?(lines[7]["state"]) && lines[7]["unit_price"].nil?, "underspecified screw must stay held")

      coa = lines.filter_map { |line| line["position"] if line["compliance"].any? { |entry| entry["label"] == "Certificate of analysis (COA) required" } }
      mtr = lines.filter_map { |line| line["position"] if line["compliance"].any? { |entry| entry["label"] == "Mill test report required" } }
      check.call(coa == [4], "COA scope expected only line 4, got #{coa.inspect}")
      # Email and PDF explicitly ask MTRs on all steel, including steel shot.
      # The CSV carries per-line notes only, so its source scope is narrower.
      expected_mtr = type == "csv" ? [1, 2, 3, 7] : [1, 2, 3, 4, 7]
      check.call(mtr == expected_mtr, "MTR scope expected #{expected_mtr.inspect}, got #{mtr.inspect}")
      normalized[type] = lines.map { |line| [line["spec"].slice("material", "grade", "form", "thickness", "width", "length", "standard"), line["quantity"], line["quantity_unit"]] }
      quote = Quote.create!(title: "formats #{type}", buyer_name: "Northline", workspace_token: "e2e", source_text: "demo #{type}", sample_data: true)
      QuoteWorkspace::ApplyResult.call(quote: quote, result: result)
      puts "#{file}: #{failures.size == before ? 'ACCEPTED' : 'FAILED'} #{quote.quote_lines.count} lines; COA #{coa.inspect}; MTR #{mtr.inspect}"
    rescue StandardError => error
      failures << "#{file}: #{error.class}: #{error.message}"
    end
  end
  reference = normalized["email"]
  normalized.each do |type, values|
    next if type == "email" || !reference

    values.each_with_index do |value, index|
      failures << "#{type}: line #{index + 1} differs from email normalized fields: #{value.inspect} versus #{reference[index].inspect}" unless value == reference[index]
    end
  end
  raise ActiveRecord::Rollback
end
failures.each { |message| warn "FAILED: #{message}" }
raise "Demo format verification failed (#{failures.size} problems)" unless failures.empty?
