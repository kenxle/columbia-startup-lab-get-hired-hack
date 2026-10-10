# frozen_string_literal: true

RSpec.describe "confirmed teaching handoff" do
  let(:text) { "Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets" }
  let(:provenance) { { "method" => "explicit_rep_teaching", "quote_id" => 1, "quote_line_id" => 2, "quote_reference" => "RFQ-0001", "taught_at" => "2026-10-10T14:00:00-04:00" } }
  let(:term) do
    { "term" => "0.060 in", "source" => "taught", "confirmed_on" => "RFQ-0001",
      "meaning" => { "fields" => { "gauge" => 16, "thickness" => 0.0625 }, "provenance" => provenance } }
  end
  let(:matcher) do
    Class.new do
      attr_reader :received
      def match(line_text:, spec:, quantity:, quantity_unit:, confirmed_terms: [])
        @received = confirmed_terms
        { "status" => "no_match", "best" => nil, "candidates" => [] }
      end
    end.new
  end
  let(:pipeline) { RfqProcessing::Pipeline.new(matcher: matcher, llm: false) }

  def process(terms, source = text, overrides: {})
    pipeline.process_line(RfqProcessing::Extractor::Line.new(text: source, location: "line 1"), position: 1, buyer_terms: terms, overrides: overrides)
    matcher.received
  end

  it "forwards the applied same-phrase term with source provenance, without mutating it" do
    original = Marshal.load(Marshal.dump(term))
    expect(process([term])).to eq([term])
    expect(term).to eq(original)
  end

  it "normalizes the app's vetted top-level provenance to meaning.provenance" do
    app_term = term.merge("meaning" => term["meaning"].except("provenance"), "provenance" => provenance)
    expect(process([app_term]).first.dig("meaning", "provenance")).to eq(provenance)
    expect(app_term["meaning"]).not_to have_key("provenance")
  end

  it "rejects claimed RFQ labels without provenance, inferred memory and malformed source IDs" do
    invalid = [term.merge("meaning" => term["meaning"].except("provenance")), term.merge("source" => "learned"),
      term.merge("confirmed_on" => "RFQ-9999"), term.merge("meaning" => term["meaning"].merge("provenance" => provenance.merge("quote_line_id" => "2"))),
      term.merge("meaning" => term["meaning"].merge("provenance" => provenance.merge("taught_at" => "unknown")))]
    invalid.each { |bad| expect(process([bad])).to eq([]) }
  end

  it "does not forward conflicting teaching or a meaning replaced by a newer buyer answer" do
    other = term.merge("meaning" => term["meaning"].merge("fields" => { "gauge" => 18, "thickness" => 0.05 }))
    expect(process([term, other])).to eq([])
    expect(process([term], text, overrides: { "thickness_in" => { "value" => 0.06, "text" => "exact 0.060", "explanation" => "buyer correction" } })).to eq([])
    expect(process([term], text, overrides: { "thickness_in" => { "value" => 0.0625, "text" => "0.060 in", "explanation" => "buyer correction" } })).to eq([])
  end

  it "does not forward substring matches or terms whose field evidence comes from other words" do
    expect(process([term], text.sub("0.060 in", "10.060 in"))).to eq([])
    expect(process([term], text.sub("0.060 in", "_0.060 in"))).to eq([])
    expect(process([term], "Stainless 304 sheet 0.060 in, 0.080 in thick, 48 x 96, 8 sheets")).to eq([])
  end

  it "withholds confirmation while any other field remains unresolved" do
    expect(process([term], text.sub(", 8 sheets", ""))).to eq([])
    reading = RfqProcessing::RulesParser.parse(text, buyer_terms: [term])
    reading.conflicts << { "code" => "independent_finish_conflict", "fields" => ["finish"], "message" => "Finish needs confirmation" }
    expect(pipeline.confirmed_terms_for([term], text, reading)).to eq([])
  end

  it "preserves legacy matcher doubles that accept only the original four keywords" do
    old = Class.new do
      def match(line_text:, spec:, quantity:, quantity_unit:)
        { "status" => "no_match", "best" => nil, "candidates" => [] }
      end
    end.new
    expect { RfqProcessing::Pipeline.new(matcher: old, llm: false).process(content: text, type: "email", buyer_terms: [term]) }.not_to raise_error
  end

  it "forwards only to services declaring the new keyword and preserves legacy call_service overrides" do
    result = Struct.new(:outcome, :candidates, :closest, :question).new("no_match", [], [], nil)
    service = Class.new do
      attr_reader :terms
      define_method(:call) do |_text, client: nil, given: {}, confirmed_terms: []|
        @terms = confirmed_terms
        result
      end
    end.new
    adapter = RfqProcessing::CatalogMatchAdapter.new(service: service)
    adapter.match(line_text: text, confirmed_terms: [term])
    expect(service.terms).to eq([term])
    [1, 3].each do |arity|
      subclass = Class.new(RfqProcessing::CatalogMatchAdapter)
      if arity == 1
        subclass.define_method(:call_service) { |_text| result }
      else
        subclass.define_method(:call_service) { |_text, _spec = {}, _quantity = nil| result }
      end
      expect(subclass.new.match(line_text: text, confirmed_terms: [term])["status"]).to eq("no_match")
    end
  end
end

RSpec.describe "confirmation payload narrowing" do
  it "does not forward ignored fields or a part-number side channel in a taught term" do
    provenance = { "method" => "explicit_rep_teaching", "quote_id" => 1, "quote_line_id" => 2, "quote_reference" => "RFQ-1", "taught_at" => "2026-10-10T14:00:00Z" }
    term = { "term" => "0.060 in", "source" => "taught", "confirmed_on" => "RFQ-1", "meaning" => { "fields" => { "thickness" => 0.0625 }, "provenance" => provenance } }
    text = "Stainless 304, 0.060 in, 48 x 96, 8 sheets"
    pipeline = RfqProcessing::Pipeline.new(llm: false)
    reading = RfqProcessing::RulesParser.parse(text, buyer_terms: [term])
    [term.merge("meaning" => term["meaning"].merge("fields" => { "thickness" => 0.0625, "quantity" => 100 })),
     term.merge("meaning" => term["meaning"].merge("fields" => { "thickness" => 0.0625, "part_number" => "UNCONFIRMED-PN" })),
     term.merge("meaning" => term["meaning"].merge("part_number" => "UNCONFIRMED-PN"))].each do |bad|
      expect(pipeline.confirmed_terms_for([bad], text, reading)).to eq([])
    end
  end
end
