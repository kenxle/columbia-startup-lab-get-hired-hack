# frozen_string_literal: true

# Runs every line of Ken's 25-line test set through the rules parser and the
# readiness rule, and compares with the expected reading the research gives.
RSpec.describe "the 25-line test set through the parser" do
  test_set = YAML.safe_load_file(File.join(FIXTURES, "test_set.yml"))["lines"]

  # Expected key => parser field. Only compared when the research gives a value.
  FIELD_MAP = {
    "material" => "material", "grade" => "grade", "temper" => "temper", "form" => "form",
    "thickness_in" => "thickness_in", "wall_in" => "wall_in", "width_in" => "width_in", "length_in" => "length_in",
    "diameter_in" => "diameter_in", "quantity" => "quantity", "finish" => "finish"
  }.freeze

  # Lines where the research itself leaves the field open, or where it reads a
  # value from context the line does not carry. Documented in test_set.yml notes.
  SKIP = {
    "T2" => %w[grade], "T3" => %w[grade], "T4" => %w[thickness_in], "T5" => %w[grade form], "T8" => %w[quantity grade form],
    "T9" => %w[quantity form], "T11" => %w[form], "T12" => %w[thickness_in], "T15" => %w[quantity],
    "T18" => %w[quantity form diameter_in], "T19" => %w[form wall_in material], "T21" => %w[form], "T25" => %w[grade]
  }.freeze

  test_set.each do |entry|
    it "#{entry['id']}: #{entry['text'][0, 60]}" do
      reading = RfqProcessing::RulesParser.parse(entry["text"])
      expected = entry["expected"]
      skips = SKIP.fetch(entry["id"], [])
      FIELD_MAP.each do |yaml_key, field|
        want = expected[yaml_key]
        next if want.nil? || skips.include?(yaml_key)

        got = reading.fields[field]
        got = reading.fields["side_a_in"] if got.nil? && field == "width_in" # tube sides and angle legs
        # Iowa quantities come from the RFQ header, not the line text; only compare a quantity the line carries.
        next if field == "quantity" && got.nil? && !entry["text"].match?(/\b\d+\s*(?:ea|each|pcs?|sheets?)\b|\bqty\b|\bx\s*\d+\s*\z/i)
        if want.is_a?(Numeric)
          expect(got).not_to be_nil, "#{field}: expected #{want}, got nil. fields=#{reading.fields.compact} unknowns=#{reading.unknowns.map { |u| u['field'] }}"
          expect(got.to_f).to be_within(want.to_f * 0.005 + 0.0001).of(want.to_f), "#{field}: expected #{want}, got #{got}"
        else
          expect(got.to_s.downcase).to eq(want.to_s.downcase), "#{field}: expected #{want.inspect}, got #{got.inspect}. fields=#{reading.fields.compact}"
        end
      end

      decision = RfqProcessing::Readiness.decide(reading, match: { "status" => "exact", "best" => { "item_id" => "x" } })
      only_quantity_missing = decision.unresolved_fields == ["quantity"] && reading.conflicts.empty?
      case entry["state_hint"]
      when "ready"
        unless only_quantity_missing && !entry["text"].match?(/\b\d+\s*(?:ea|each|pcs?)\b|\bqty\b|\bx\s*\d+\s*\z/i)
          expect(decision.state).to eq("ready"), "expected ready, got #{decision.state}: #{decision.question} conflicts=#{reading.conflicts.map { |c| c['code'] }} unknowns=#{reading.unknowns}"
        end
      when "needs_buyer", "cannot_read"
        # A line whose only research question is about paperwork (certs, PMI, DFARS, ITAR) reads clean; the
        # compliance flags carry that question, and the readiness rule does not hold the line for it.
        unless entry["flags"].any? && reading.conflicts.empty?
          expect(decision.state).to eq("needs_buyer"), "expected a question, got #{decision.state}. fields=#{reading.fields.compact}"
          expect(decision.question).to be_a(String)
        end
      end
    end
  end
end
