# frozen_string_literal: true

RSpec.describe RfqProcessing::LlmParser do
  # A stand-in for Anthropic::Client: records the create params and returns a canned
  # response, or raises when the response is an exception. No network, no key.
  StubClient = Struct.new(:response, :params) do
    def messages = self

    def create(**params)
      self.params = params
      raise response if response.is_a?(Exception)

      response
    end
  end
  TextBlock = Struct.new(:type, :text)
  Response = Struct.new(:content)

  def claude_says(fields: {}, evidence: [], unclear: [])
    json = JSON.generate({ "fields" => fields, "evidence" => evidence, "unclear" => unclear })
    StubClient.new(Response.new([TextBlock.new(:text, json)]))
  end

  def parser_for(client) = described_class.new(client: client)

  def with_env(overrides)
    saved = overrides.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # The Reading the rules produce when the material word is misspelled and the grade is not
  # read: a gauge with no material, so thickness is an unknown. (The real rules infer stainless
  # from "304", so this state is built by hand to exercise the fill path on its own.)
  def no_material_reading
    RfqProcessing::RulesParser::Reading.new(
      fields: { "form" => "sheet", "gauge" => 16, "quantity" => 5, "quantity_unit" => "each", "width_in" => 48, "length_in" => 96,
                "material" => nil, "grade" => nil, "thickness_in" => nil },
      evidence: { "gauge" => { "text" => "16ga", "location" => "line 1, chars 15-18", "explanation" => "a gauge number is not a thickness" } },
      confidence: { "gauge" => 0.95 },
      assumptions: [], rules_used: [],
      conflicts: [{ "code" => "material_missing_with_gauge", "message" => "No material is written.", "fields" => %w[material thickness_in] }],
      unknowns: [{ "field" => "material", "reason" => "no material is written" },
                 { "field" => "thickness_in", "reason" => "16 gauge has 3 readings with no material" }],
      location: "line 1"
    )
  end

  describe "#refine" do
    let(:line) { "Stnless 304 sht 16ga 4x8 qty 5" }

    it "fills material and grade the rules left empty, from quoted words, and leaves thickness to the rules" do
      client = claude_says(
        fields: { "material" => "stainless steel", "grade" => "304", "form" => "sheet", "thickness_in" => nil, "quantity" => 5 },
        evidence: [{ "field" => "material", "text" => "Stnless", "note" => "misspelling of stainless", "confidence" => 0.92 },
                   { "field" => "grade", "text" => "304", "note" => "stainless grade 304", "confidence" => 0.95 },
                   { "field" => "form", "text" => "sht", "note" => "sht means sheet", "confidence" => 0.9 },
                   { "field" => "quantity", "text" => "qty 5", "note" => "quantity as written", "confidence" => 0.95 }],
        unclear: ["16ga is a gauge, not a thickness; the table depends on the material"]
      )
      reading = no_material_reading
      result = parser_for(client).refine(reading, line)

      expect(result).to equal(reading)
      expect(result["material"]).to eq("stainless steel")
      expect(result["grade"]).to eq("304")
      expect(result.evidence["material"]).to eq("text" => "Stnless", "location" => "line 1", "explanation" => "read by Claude: misspelling of stainless")
      expect(result.confidence["material"]).to eq(0.92)
      expect(result.confidence["grade"]).to eq(0.95)
      expect(result.rules_used).to include("Claude read: material", "Claude read: grade")
      expect(result.unknowns.map { |u| u["field"] }).not_to include("material")
      # Thickness is the rules' gauge math, not Claude's: refine leaves it exactly as the rules had it.
      expect(result["thickness_in"]).to be_nil
      expect(result.unknowns.map { |u| u["field"] }).to include("thickness_in")
      # Fields the rules already had keep the rules' evidence, with no Claude note.
      expect(result["form"]).to eq("sheet")
      expect(result.rules_used).not_to include("Claude read: form", "Claude read: quantity")
      expect(result.conflicts.map { |c| c["code"] }).to eq(["material_missing_with_gauge"])
    end

    it "never overwrites what the rules settled on the real rules reading of the same line" do
      reading = RfqProcessing::RulesParser.parse(line)
      before = reading.fields.dup
      client = claude_says(
        fields: { "material" => "Stainless Steel", "grade" => "304", "thickness_in" => nil },
        evidence: [{ "field" => "material", "text" => "stnless", "note" => "misspelling", "confidence" => 0.95 },
                   { "field" => "grade", "text" => "304", "note" => "grade", "confidence" => 0.95 }]
      )
      result = parser_for(client).refine(reading, line)

      expect(result.fields).to eq(before)
      expect(result["thickness_in"]).to eq(0.0625)
      expect(result.conflicts).to be_empty # same material, compared case-insensitively
      expect(result.rules_used).not_to include(a_string_starting_with("Claude read:"))
    end

    it "drops a value whose quoted evidence is not in the line, and one with no evidence at all" do
      client = claude_says(
        fields: { "finish" => "2B", "coating" => "galvanized", "temper" => "T6" },
        evidence: [{ "field" => "finish", "text" => "2B finish", "note" => "finish", "confidence" => 0.99 },
                   { "field" => "coating", "text" => "galv", "note" => "coating", "confidence" => 0.99 }]
      )
      reading = no_material_reading
      result = parser_for(client).refine(reading, line)

      expect(result["finish"]).to be_nil
      expect(result["coating"]).to be_nil
      expect(result["temper"]).to be_nil
      expect(result.evidence).not_to include("finish", "coating", "temper")
      expect(result.rules_used).to be_empty
    end

    it "adds an llm_disagrees conflict at high confidence and keeps the rules' value" do
      text = "304 SS sheet 0.060 x 48 x 96 qty 2"
      reading = RfqProcessing::RulesParser.parse(text)
      expect(reading["width_in"]).to eq(48)
      client = claude_says(
        fields: { "width_in" => 36, "material" => "stainless steel" },
        evidence: [{ "field" => "width_in", "text" => "48 x 96", "note" => "width", "confidence" => 0.95 },
                   { "field" => "material", "text" => "SS", "note" => "stainless", "confidence" => 0.95 }]
      )
      result = parser_for(client).refine(reading, text)

      expect(result["width_in"]).to eq(48)
      conflicts = result.conflicts.select { |c| c["code"] == "llm_disagrees" }
      expect(conflicts.size).to eq(1)
      expect(conflicts.first["fields"]).to eq(["width_in"])
      expect(conflicts.first["message"]).to include("36", "48")
    end

    it "does not record a disagreement below 0.9 confidence, within 1%, or on a case difference" do
      text = "304 SS sheet 0.060 x 48 x 96 qty 2"
      reading = RfqProcessing::RulesParser.parse(text)
      client = claude_says(
        fields: { "width_in" => 36, "length_in" => 96.5, "material" => "STAINLESS STEEL" },
        evidence: [{ "field" => "width_in", "text" => "48", "note" => "width", "confidence" => 0.6 },
                   { "field" => "length_in", "text" => "96", "note" => "length", "confidence" => 0.99 },
                   { "field" => "material", "text" => "SS", "note" => "stainless", "confidence" => 0.99 }]
      )
      result = parser_for(client).refine(reading, text)

      expect(result["width_in"]).to eq(48)
      expect(result["length_in"]).to eq(96)
      expect(result.conflicts.map { |c| c["code"] }).not_to include("llm_disagrees")
    end

    it "returns the reading untouched when read gives nil" do
      reading = no_material_reading
      snapshot = Marshal.load(Marshal.dump(reading))
      result = nil
      expect { result = parser_for(StubClient.new(RuntimeError.new("boom"))).refine(reading, line) }.to output(/boom/).to_stderr

      expect(result).to equal(reading)
      expect(result).to eq(snapshot)
    end
  end

  describe "#read" do
    it "returns nil and warns when the client raises" do
      parser = parser_for(StubClient.new(RuntimeError.new("rate limited")))
      result = nil
      expect { result = parser.read("304 SS sheet") }.to output(/Claude read failed.*rate limited/).to_stderr
      expect(result).to be_nil
    end

    it "returns nil when the response has no text block" do
      parser = parser_for(StubClient.new(Response.new([])))
      expect { expect(parser.read("304 SS sheet")).to be_nil }.to output(/no text block/).to_stderr
    end

    it "returns the reading shape with every schema field present and typed values" do
      client = claude_says(fields: { "material" => " aluminum ", "quantity" => "12", "thickness_in" => 0.125 },
                           evidence: [{ "field" => "material", "text" => "alum", "note" => "n", "confidence" => "0.8" }],
                           unclear: ["temper"])
      result = parser_for(client).read("alum plate 0.125 qty 12")

      expect(result["fields"].keys).to match_array(described_class::FIELDS)
      expect(result["fields"]).to include("material" => "aluminum", "quantity" => 12, "thickness_in" => 0.125, "grade" => nil)
      expect(result["evidence"]).to eq([{ "field" => "material", "text" => "alum", "note" => "n", "confidence" => 0.8 }])
      expect(result["unclear"]).to eq(["temper"])
    end

    it "calls messages.create with the model, max_tokens, system prompt, and a json_schema output format" do
      client = claude_says
      parser_for(client).read("304 SS sheet 16ga 4x8")
      params = client.params

      expect(params[:model]).to eq("claude-opus-5-5")
      expect(params[:max_tokens]).to eq(2048)
      expect(params[:system_]).to include("gauge number is not a thickness")
      expect(params[:messages]).to eq([{ role: "user", content: "304 SS sheet 16ga 4x8" }])
      expect(params[:output_config]).to eq({ format: { type: "json_schema", schema: described_class::SCHEMA } })
      expect(params).not_to include(:thinking, :tool_choice, :tools)
    end

    it "uses a schema where every object has additionalProperties false and a required list, with no numeric bounds" do
      objects = []
      walk = lambda do |node|
        case node
        when Hash
          objects << node if node["type"] == "object"
          expect(node.keys).not_to include("minimum", "maximum", "multipleOf", "minLength", "maxLength")
          node.each_value { |v| walk.call(v) }
        when Array then node.each { |v| walk.call(v) }
        end
      end
      walk.call(described_class::SCHEMA)

      expect(objects.size).to eq(3)
      objects.each do |o|
        expect(o["additionalProperties"]).to be(false)
        expect(o["required"]).to match_array(o["properties"].keys)
      end
    end
  end

  describe ".from_env" do
    it "returns nil when neither ANTHROPIC_API_KEY nor ANTHROPIC_AUTH_TOKEN is set" do
      with_env("ANTHROPIC_API_KEY" => nil, "ANTHROPIC_AUTH_TOKEN" => nil) do
        expect(described_class.from_env).to be_nil
      end
    end

    it "treats a blank key as unset" do
      with_env("ANTHROPIC_API_KEY" => "  ", "ANTHROPIC_AUTH_TOKEN" => nil) do
        expect(described_class.from_env).to be_nil
      end
    end

    it "uses a client passed in without touching the environment" do
      with_env("ANTHROPIC_API_KEY" => nil, "ANTHROPIC_AUTH_TOKEN" => nil) do
        expect(described_class.from_env(client: claude_says)).to be_a(described_class)
      end
    end

    it "builds a parser when a key is set (requires the SDK lazily, no network call)" do
      with_env("ANTHROPIC_API_KEY" => "test-key-not-real", "ANTHROPIC_AUTH_TOKEN" => nil) do
        expect(described_class.from_env).to be_a(described_class)
      end
    end
  end
end
