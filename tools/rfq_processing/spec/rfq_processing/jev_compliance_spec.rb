# frozen_string_literal: true

RSpec.describe RfqProcessing::JevCompliance do
  let(:flags) { RfqProcessing::Compliance.flags(text: "304 sheet domestic") }

  def client_with(probability)
    Class.new do
      attr_reader :questions
      define_method(:evaluate) do |state:, questions:|
        @questions = questions
        { "model" => "jev-1.13.0", "probabilities" => questions.to_h { |id, _| [id, probability] } }
      end
    end.new
  end

  it "adds a probability note without changing the deterministic flag or source evidence" do
    before = Marshal.load(Marshal.dump(flags))
    client = client_with(0.12)
    result = described_class.new(client: client).annotate(flags: flags, text: "304 sheet domestic", spec: {})
    expect(flags).to eq(before)
    expect(result.size).to eq(flags.size)
    expect(result.first.except("note", "jev")).to eq(flags.first.except("note"))
    expect(result.first["note"]).to include("Jev review: probability this requirement applies: 12.0%. Ambiguous trigger [domestic] requires rep review.")
    expect(result.first["jev"]).to include("status" => "evaluated", "probability" => 0.12, "model" => "jev-1.13.0")
    expect(client.questions.values.first["instructions"]["trigger_words"]).to eq("domestic")
  end

  it "leaves flags identical when disabled and retains them on provider failure" do
    expect(described_class.new(client: nil).annotate(flags: flags, text: "domestic", spec: {})).to eq(flags)
    client = double("client", evaluate: nil)
    result = described_class.new(client: client).annotate(flags: flags, text: "domestic", spec: {})
    expect(result.first["label"]).to eq(flags.first["label"])
    expect(result.first["note"]).to include("Jev review unavailable", "Ambiguous trigger [domestic] requires rep review.")
    expect(result.first["jev"]["status"]).to eq("unavailable")
  end

  it "does not call Jev for explicit ordinary paperwork and caps doubtful flags at four" do
    client = client_with(0.6)
    ordinary = RfqProcessing::Compliance.flags(text: "MTR required DFARS")
    expect(described_class.new(client: client).annotate(flags: ordinary, text: "MTR required DFARS", spec: {})).to eq(ordinary)
    expect(client.questions).to be_nil
    many = Array.new(6) { flags.first.dup }
    result = described_class.new(client: client).annotate(flags: many, text: "domestic", spec: {})
    expect(client.questions.size).to eq(4)
    expect(result.count { |flag| flag["jev"] }).to eq(4)
    expect(result.size).to eq(6)
  end

  it "does not activate an environment-configured Jev client without explicit opt-in" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("JEV_API_KEY").and_return("offline-test-key")
    expect(RfqProcessing::JevClient).not_to receive(:from_env)
    expect(Net::HTTP).not_to receive(:new)
    [nil, false].each do |jev|
      result = RfqProcessing.process(content: "304 stainless sheet 16 ga 4x8 5 lb domestic", llm: false, jev: jev)
      expect(result["lines"].first.dig("processing", "compliance_detail")).to all(satisfy { |flag| !flag.key?("jev") })
    end
  end

  it "allows explicit jev: true to load the environment client independently of llm: false" do
    client = client_with(0.2)
    expect(RfqProcessing::JevClient).to receive(:from_env).once.and_return(client)
    result = RfqProcessing.process(content: "304 stainless sheet 16 ga 4x8 5 lb domestic", llm: false, jev: true)
    expect(client.questions).not_to be_empty
    expect(result["lines"].first.dig("processing", "compliance_detail").first.dig("jev", "probability")).to eq(0.2)
  end

  it "cannot change pipeline fields, flags, readiness, questions or prices" do
    text = "304 stainless sheet 16 ga 4x8 5 lb domestic"
    plain = RfqProcessing.process(content: text, llm: false, jev: false)
    reviewed = RfqProcessing.process(content: text, llm: false, jev: client_with(0.01))
    a, b = plain["lines"].first, reviewed["lines"].first
    expect(b.except("compliance", "processing")).to eq(a.except("compliance", "processing"))
    expect(b["processing"].except("compliance_detail")).to eq(a["processing"].except("compliance_detail"))
    expect(b["compliance"].map { |flag| flag.except("note") }).to eq(a["compliance"].map { |flag| flag.except("note") })
    expect(b["processing"]["compliance_detail"].first["jev"]["probability"]).to eq(0.01)
  end
end
