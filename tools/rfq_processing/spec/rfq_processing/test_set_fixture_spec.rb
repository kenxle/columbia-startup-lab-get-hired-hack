# frozen_string_literal: true

RSpec.describe "test_set.yml fixture" do
  let(:lines) { YAML.safe_load_file(File.join(FIXTURES, "test_set.yml")).fetch("lines") }
  let(:by_id) { lines.to_h { |line| [line["id"], line] } }

  required_keys = %w[id kind source text context expected reading state_hint ask flags notes]
  state_hints = %w[ready needs_buyer cannot_read]

  it "holds T1 through T25 in order" do
    expect(lines.map { |line| line["id"] }).to eq((1..25).map { |n| "T#{n}" })
  end

  it "gives every entry the same keys" do
    lines.each do |line|
      expect(line.keys).to include(*required_keys), "#{line["id"]} is missing #{required_keys - line.keys}"
    end
  end

  it "uses one of the three state hints on every entry" do
    lines.each do |line|
      expect(state_hints).to include(line["state_hint"]), "#{line["id"]} has state_hint #{line["state_hint"].inspect}"
    end
  end

  it "keeps every numeric thickness positive and under 3 in" do
    lines.each do |line|
      thickness = line.fetch("expected").fetch("thickness_in")
      next unless thickness.is_a?(Numeric)

      expect(thickness).to be > 0, "#{line["id"]} thickness #{thickness}"
      expect(thickness).to be < 3, "#{line["id"]} thickness #{thickness}"
    end
  end

  it "reads T1 (16 gauge stainless) as 0.0625 in" do
    expect(by_id.fetch("T1").fetch("expected").fetch("thickness_in")).to eq(0.0625)
  end

  it "reads T11 (0.060 written as a decimal) as 0.060 in, not a gauge value" do
    expect(by_id.fetch("T11").fetch("expected").fetch("thickness_in")).to eq(0.060)
  end
end
