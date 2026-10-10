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
  Response = Struct.new(:content, :model)

  # A stand-in for OpenAiCompatibleClient: records the chat params and returns a canned
  # reply hash, or nil when the real client would have given up.
  ChatStub = Struct.new(:reply, :params, :model) do
    def chat(**params)
      self.params = params
      reply
    end
  end

  LLM_ENV = %w[ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL NICRRON_API_KEY NICRRON_BASE_URL NICRRON_MODEL
               RFQ_LLM_PROVIDER].freeze

  def claude_says(fields: {}, evidence: [], unclear: [], model: "claude-opus-5")
    json = JSON.generate({ "fields" => fields, "evidence" => evidence, "unclear" => unclear })
    StubClient.new(Response.new([TextBlock.new(:text, json)], model))
  end

  def gateway_says(fields: {}, evidence: [], unclear: [], model: "anthropic/claude-opus-5", fence: nil)
    json = JSON.generate({ "fields" => fields, "evidence" => evidence, "unclear" => unclear })
    text = fence ? "#{fence}\n#{json}\n```" : json
    ChatStub.new({ "text" => text, "model" => model }, nil, "anthropic/claude-opus-5")
  end

  def parser_for(client) = described_class.new(client: client)

  def with_env(overrides)
    saved = overrides.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # Every LLM variable cleared, then the overrides applied; all restored afterwards.
  def with_llm_env(overrides = {}, &block)
    with_env(LLM_ENV.to_h { |k| [k, nil] }.merge(overrides), &block)
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

  it "never logs sentinel content from exceptions, malformed JSON, or response model names" do
    sentinel = "PRIVATE_RFQ_CONTENT_SENTINEL"
    clients = [
      StubClient.new(RuntimeError.new(sentinel)),
      StubClient.new(Response.new([TextBlock.new(:text, sentinel)], "claude-opus-5")),
      ChatStub.new({ "text" => sentinel, "model" => "anthropic/claude-opus-5" }, nil, "anthropic/claude-opus-5"),
      gateway_says(model: sentinel)
    ]
    clients.each do |client|
      expect { expect(parser_for(client).read(sentinel)).to be_nil }
        .to output(a_string_matching(/\ALlmParser:(?!.*#{Regexp.escape(sentinel)}).*\z/m)).to_stderr
    end
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

    it "records the model once in rules_used when Claude filled a field" do
      client = claude_says(
        fields: { "material" => "stainless steel", "grade" => "304" },
        evidence: [{ "field" => "material", "text" => "Stnless", "note" => "misspelling", "confidence" => 0.92 },
                   { "field" => "grade", "text" => "304", "note" => "grade", "confidence" => 0.95 }]
      )
      result = parser_for(client).refine(no_material_reading, line)

      expect(result.rules_used).to eq(["Claude read: material", "Claude read: grade", "Claude model: claude-opus-5"])
    end

    it "records the gateway's model name when the reading came through the gateway" do
      client = gateway_says(fields: { "material" => "stainless steel" },
                            evidence: [{ "field" => "material", "text" => "Stnless", "note" => "misspelling", "confidence" => 0.92 }])
      result = parser_for(client).refine(no_material_reading, line)

      expect(result["material"]).to eq("stainless steel")
      expect(result.rules_used).to eq(["Claude read: material", "Claude model: anthropic/claude-opus-5"])
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
      expect(result.rules_used).not_to include(a_string_starting_with("Claude read:"), a_string_starting_with("Claude model:"))
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
      expect(result.rules_used).to be_empty # nothing used, so no model line either
    end

    it "adds an llm_disagrees conflict at high confidence, keeps the rules' value, and records the model" do
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
      expect(result.rules_used.count("Claude model: claude-opus-5")).to eq(1)
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
      expect(result.rules_used).not_to include(a_string_starting_with("Claude model:"))
    end

    def state_for(reading)
      RfqProcessing::Readiness.decide(reading, match: { "status" => "exact" }).state
    end

    [0.1, -1, 1.1, "1e999"].each do |confidence|
      it "keeps missing material held for invalid or low confidence #{confidence}" do
        text = "mystery sheet 0.0625 48x96 qty 5"
        client = gateway_says(fields: { "material" => "stainless steel" },
                              evidence: [{ "field" => "material", "text" => "mystery", "note" => "tentative", "confidence" => confidence }])
        reading = parser_for(client).refine(RfqProcessing::RulesParser.parse(text), text)
        expect(reading["material"]).to be_nil
        expect(state_for(reading)).to eq("needs_buyer")
      end
    end

    it "rejects SS inside brass and preserves the material hold" do
      text = "brass sheet 0.0625 48x96 qty 5"
      client = gateway_says(fields: { "material" => "stainless steel" },
                            evidence: [{ "field" => "material", "text" => "SS", "note" => "stainless", "confidence" => 0.99 }])
      reading = parser_for(client).refine(RfqProcessing::RulesParser.parse(text), text)
      expect(reading["material"]).to be_nil
      expect(state_for(reading)).to eq("needs_buyer")
    end

    it "accepts whole-token evidence with case and whitespace normalization" do
      text = "STNLESS   METAL sheet 0.0625 48x96 qty 5"
      client = gateway_says(fields: { "material" => "stainless steel" },
                            evidence: [{ "field" => "material", "text" => "stnless metal", "note" => "misspelling", "confidence" => 0.9 }])
      reading = parser_for(client).refine(RfqProcessing::RulesParser.parse(text), text)
      expect(reading["material"]).to eq("stainless steel")
      expect(state_for(reading)).to eq("ready")
    end

    it "holds a complete reading when Claude also declares uncertainty" do
      text = "mystery sheet 0.0625 48x96 qty 5"
      client = gateway_says(fields: { "material" => "stainless steel" },
                            evidence: [{ "field" => "material", "text" => "mystery", "note" => "tentative", "confidence" => 0.95 }],
                            unclear: ["material is not identified"])
      reading = parser_for(client).refine(RfqProcessing::RulesParser.parse(text), text)
      expect(state_for(reading)).to eq("needs_buyer")
      expect(reading.conflicts.map { |c| c["code"] }).to include("llm_unclear")
      expect(reading.conflicts.last["message"]).not_to include("material is not identified")
    end

    [0, -5, "1e999", "NaN", "1e-9"].each do |quantity|
      it "leaves demand unresolved for invalid quantity #{quantity}" do
        text = "steel shot S-330, amount to confirm"
        client = gateway_says(fields: { "quantity" => quantity },
                              evidence: [{ "field" => "quantity", "text" => "amount", "note" => "quantity", "confidence" => 0.95 }])
        reading = parser_for(client).refine(RfqProcessing::RulesParser.parse(text), text)
        expect(reading["quantity"]).to be_nil
        expect(state_for(reading)).to eq("needs_buyer")
      end
    end

    it "returns the reading untouched when read gives nil" do
      reading = no_material_reading
      snapshot = Marshal.load(Marshal.dump(reading))
      result = nil
      expect { result = parser_for(StubClient.new(RuntimeError.new("boom"))).refine(reading, line) }.to output(/RuntimeError/).to_stderr

      expect(result).to equal(reading)
      expect(result).to eq(snapshot)
    end
  end

  describe "#read through the Anthropic client" do
    it "returns nil and warns when the client raises" do
      parser = parser_for(StubClient.new(RuntimeError.new("rate limited")))
      result = nil
      expect { result = parser.read("304 SS sheet") }.to output(/Claude read failed.*RuntimeError/).to_stderr
      expect(result).to be_nil
    end

    it "returns nil when the response has no text block" do
      parser = parser_for(StubClient.new(Response.new([], "claude-opus-5")))
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

    it "calls messages.create with Opus 5, max_tokens, the system prompt, and a json_schema output format" do
      client = claude_says
      parser_for(client).read("304 SS sheet 16ga 4x8")
      params = client.params

      expect(params[:model]).to eq("claude-opus-5")
      expect(params[:max_tokens]).to eq(2048)
      expect(params[:system_]).to include("gauge number is not a thickness")
      expect(params[:messages]).to eq([{ role: "user", content: "304 SS sheet 16ga 4x8" }])
      expect(params[:output_config]).to eq({ format: { type: "json_schema", schema: described_class::SCHEMA } })
      expect(params).not_to include(:thinking, :tool_choice, :tools)
    end

    it "sends the model it was built with" do
      client = claude_says
      described_class.new(client: client, model: "claude-opus-5-20260901").read("304 SS sheet")
      expect(client.params[:model]).to eq("claude-opus-5-20260901")
    end

    it "accepts a response that names the requested model, with or without a dated snapshot suffix" do
      ["claude-opus-5", "claude-opus-5-20260901", :"claude-opus-5"].each do |name|
        client = claude_says(fields: { "material" => "aluminum" }, model: name)
        expect(parser_for(client).read("alum plate")["fields"]["material"]).to eq("aluminum")
      end
    end

    it "drops the reading with a warning when the response names another model" do
      client = claude_says(fields: { "material" => "aluminum" }, model: "claude-opus-5-5")
      result = nil
      expect { result = parser_for(client).read("alum plate") }
        .to output("LlmParser: model identity mismatch; reading dropped\n").to_stderr
      expect(result).to be_nil
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

  describe "#read through an OpenAI-compatible client" do
    it "calls chat with the system prompt, the line, the schema, and max_tokens, and parses a ```json fence" do
      client = gateway_says(fields: { "material" => "aluminum", "quantity" => "12" },
                            evidence: [{ "field" => "material", "text" => "alum", "note" => "n", "confidence" => 0.8 }],
                            fence: "```json")
      result = parser_for(client).read("alum plate 0.125 qty 12")

      expect(client.params).to eq(system: described_class::SYSTEM_PROMPT, user: "alum plate 0.125 qty 12",
                                  schema: described_class::SCHEMA, max_tokens: 2048)
      expect(result["fields"]).to include("material" => "aluminum", "quantity" => 12, "grade" => nil)
      expect(result["fields"].keys).to match_array(described_class::FIELDS)
      expect(result["evidence"]).to eq([{ "field" => "material", "text" => "alum", "note" => "n", "confidence" => 0.8 }])
    end

    it "parses bare JSON, a plain ``` fence, and surrounding whitespace" do
      [nil, "```", "```JSON"].each do |fence|
        client = gateway_says(fields: { "grade" => "6061" }, fence: fence)
        client.reply["text"] = "  \n#{client.reply['text']}\n\n"
        expect(parser_for(client).read("6061 bar")["fields"]["grade"]).to eq("6061")
      end
    end

    it "drops the reading with a warning when the gateway answers with another model" do
      client = gateway_says(fields: { "material" => "aluminum" }, model: "anthropic/claude-sonnet-4-6")
      result = nil
      expect { result = parser_for(client).read("alum plate") }
        .to output("LlmParser: model identity mismatch; reading dropped\n")
        .to_stderr
      expect(result).to be_nil
    end

    it "treats Opus 5.5 as a different model from Opus 5" do
      client = gateway_says(fields: { "material" => "aluminum" }, model: "anthropic/claude-opus-5-5")
      expect { expect(parser_for(client).read("alum plate")).to be_nil }.to output(/model identity mismatch; reading dropped/).to_stderr
    end

    it "accepts the requested model with a date suffix, another provider prefix, or different case" do
      ["anthropic/claude-opus-5", "Anthropic/Claude-Opus-5", "anthropic/claude-opus-5-20260901", "claude-opus-5",
       "claude-opus-5@20260901"].each do |name|
        client = gateway_says(fields: { "material" => "aluminum" }, model: name)
        expect(parser_for(client).read("alum plate")["fields"]["material"]).to eq("aluminum")
      end
    end

    it "returns nil quietly when the client already gave up" do
      client = ChatStub.new(nil, nil, "anthropic/claude-opus-5")
      result = :unset
      expect { result = parser_for(client).read("alum plate") }.not_to output.to_stderr
      expect(result).to be_nil
    end

    it "drops responses without model identity instead of attributing them to the requested model" do
      [nil, "", "   "].each do |name|
        [gateway_says(model: name), claude_says(model: name)].each do |client|
          expect { expect(parser_for(client).read("alum plate")).to be_nil }
            .to output(/no model identity; reading dropped/).to_stderr
        end
      end
    end

    it "returns nil and warns when the content is not JSON" do
      client = ChatStub.new({ "text" => "I cannot read this line.", "model" => "anthropic/claude-opus-5" }, nil, "anthropic/claude-opus-5")
      expect { expect(parser_for(client).read("alum plate")).to be_nil }.to output(/reply is not JSON/).to_stderr
    end
  end

  describe "#describe, #provider, and #model" do
    it "names the Anthropic provider and Opus 5 for an SDK-style client" do
      parser = parser_for(claude_says)
      expect(parser.provider).to eq("anthropic")
      expect(parser.model).to eq("claude-opus-5")
      expect(parser.describe).to eq("provider" => "anthropic", "model" => "claude-opus-5")
    end

    it "names nicrron and the client's own model for a chat client" do
      parser = parser_for(ChatStub.new(nil, nil, "anthropic/claude-opus-5-20260901"))
      expect(parser.describe).to eq("provider" => "nicrron", "model" => "anthropic/claude-opus-5-20260901")
    end

    it "falls back to the Nicrron default when a chat client names no model, and an explicit model wins" do
      expect(parser_for(ChatStub.new(nil, nil, nil)).describe).to eq("provider" => "nicrron", "model" => "anthropic/claude-opus-5")
      parser = described_class.new(client: claude_says, model: "claude-opus-5-20260901")
      expect(parser.describe).to eq("provider" => "anthropic", "model" => "claude-opus-5-20260901")
    end

    it "compares model names the way the readings are checked: same id, dated snapshot ok, 5.5 is not 5" do
      same = described_class.method(:same_model?)
      expect(same.call("anthropic/claude-opus-5", "anthropic/claude-opus-5")).to be(true)
      expect(same.call("anthropic/claude-opus-5", "Claude-Opus-5")).to be(true)
      expect(same.call("claude-opus-5", "anthropic/claude-opus-5-20260901")).to be(true)
      expect(same.call("claude-opus-5", "claude-opus-5@20260901")).to be(true)
      expect(same.call("claude-opus-5", "claude-opus-5-5")).to be(false)
      expect(same.call("claude-opus-5", "anthropic/claude-sonnet-4-6")).to be(false)
      expect(same.call("claude-opus-5", "")).to be(false)
      expect(described_class.bare_model_name(" Anthropic/Claude-Opus-5 ")).to eq("claude-opus-5")
    end

    it "keeps MODEL as an alias of the Anthropic model id" do
      expect(described_class::MODEL).to eq("claude-opus-5")
      expect(described_class::ANTHROPIC_MODEL).to eq("claude-opus-5")
      expect(described_class::NICRRON_MODEL).to eq("anthropic/claude-opus-5")
      expect(described_class::NICRRON_BASE_URL).to eq("https://api.nicrron.ai/v1")
    end
  end

  describe ".from_env" do
    it "returns nil when no key is set" do
      with_llm_env do
        expect(described_class.from_env).to be_nil
      end
    end

    it "treats blank keys as unset" do
      with_llm_env("ANTHROPIC_API_KEY" => "  ", "NICRRON_API_KEY" => "") do
        expect(described_class.from_env).to be_nil
      end
    end

    it "uses a client passed in without touching the environment, and tells the two kinds apart" do
      with_llm_env do
        expect(described_class.from_env(client: claude_says).describe).to eq("provider" => "anthropic", "model" => "claude-opus-5")
        expect(described_class.from_env(client: gateway_says).describe).to eq("provider" => "nicrron", "model" => "anthropic/claude-opus-5")
      end
    end

    it "picks Nicrron with the default base url and model when NICRRON_API_KEY is set" do
      with_llm_env("NICRRON_API_KEY" => "test-key-not-real") do
        parser = described_class.from_env

        expect(parser.describe).to eq("provider" => "nicrron", "model" => "anthropic/claude-opus-5")
        expect(parser.client).to be_a(RfqProcessing::OpenAiCompatibleClient)
        expect(parser.client.base_url).to eq("https://api.nicrron.ai/v1")
        expect(parser.client.model).to eq("anthropic/claude-opus-5")
      end
    end

    it "honors NICRRON_BASE_URL and NICRRON_MODEL" do
      with_llm_env("NICRRON_API_KEY" => "test-key-not-real", "NICRRON_BASE_URL" => "https://gateway.example/v2/",
                   "NICRRON_MODEL" => "anthropic/claude-opus-5-20260901") do
        parser = described_class.from_env

        expect(parser.describe).to eq("provider" => "nicrron", "model" => "anthropic/claude-opus-5-20260901")
        expect(parser.client.base_url).to eq("https://gateway.example/v2")
        expect(parser.client.url).to eq("https://gateway.example/v2/chat/completions")
        expect(parser.client.model).to eq("anthropic/claude-opus-5-20260901")
      end
    end

    it "builds the Anthropic parser with Opus 5 when only an Anthropic key is set (requires the SDK lazily, no network call)" do
      with_llm_env("ANTHROPIC_API_KEY" => "test-key-not-real") do
        parser = described_class.from_env
        expect(parser.describe).to eq("provider" => "anthropic", "model" => "claude-opus-5")
        expect(parser.client.class.name).to eq("Anthropic::Client")
      end
      with_llm_env("ANTHROPIC_AUTH_TOKEN" => "test-token-not-real", "ANTHROPIC_MODEL" => "claude-opus-5-20260901") do
        expect(described_class.from_env.describe).to eq("provider" => "anthropic", "model" => "claude-opus-5-20260901")
      end
    end

    it "prefers Nicrron when both keys are set, and RFQ_LLM_PROVIDER forces either one" do
      both = { "NICRRON_API_KEY" => "test-key-not-real", "ANTHROPIC_API_KEY" => "test-key-not-real" }
      with_llm_env(both) { expect(described_class.from_env.provider).to eq("nicrron") }
      with_llm_env(both.merge("RFQ_LLM_PROVIDER" => "anthropic")) { expect(described_class.from_env.describe).to eq("provider" => "anthropic", "model" => "claude-opus-5") }
      with_llm_env(both.merge("RFQ_LLM_PROVIDER" => "nicrron")) { expect(described_class.from_env.provider).to eq("nicrron") }
      with_llm_env(both.merge("RFQ_LLM_PROVIDER" => "Anthropic")) { expect(described_class.from_env.provider).to eq("anthropic") }
    end

    it "turns the step off with a warning when RFQ_LLM_PROVIDER names a provider without a key, or an unknown one" do
      with_llm_env("ANTHROPIC_API_KEY" => "test-key-not-real", "RFQ_LLM_PROVIDER" => "nicrron") do
        expect { expect(described_class.from_env).to be_nil }.to output(/configured provider key is not set/).to_stderr
      end
      with_llm_env("NICRRON_API_KEY" => "test-key-not-real", "RFQ_LLM_PROVIDER" => "openai") do
        expect { expect(described_class.from_env).to be_nil }.to output(/unsupported provider configuration/).to_stderr
      end
    end
  end
end
