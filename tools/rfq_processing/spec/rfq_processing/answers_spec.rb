# frozen_string_literal: true

# Workflow decision W3 (docs/product/WORKFLOW.md): a buyer's answer reruns only
# the answered lines; an answer that covers the whole RFQ reruns every line
# (guard 1); each rerun line records the run it came from (guard 4).
RSpec.describe RfqProcessing::Answers do
  let(:row) do
    { "pn" => "RC-SS304-SHT-16GA-48X96-2B", "item_id" => "RC-SS304-SHT-16GA-48X96-2B", "form" => "sheet", "material" => "stainless steel",
      "grade" => "304", "thickness_in" => 0.0625, "width_in" => 48, "length_in" => 96, "finish" => "2B", "description" => "304 sheet 16 ga 48x96 2B",
      "list_price_usd_per_lb" => 2.5, "list_price_source" => { "kind" => "RudCo website list price", "text" => "$2.50/lb", "url" => "https://www.rud-co.com" } }
  end
  let(:catalog) { [row] }
  let(:pipeline) { RfqProcessing::Pipeline.new(catalog: catalog) }
  let(:no_material) { "16 ga sheet 4x8 qty 20" }
  let(:clean) { "304 stainless sheet 16 ga 4x8 qty 5" }

  def process(content, catalog)
    RfqProcessing.process(content: content, type: "email", catalog: catalog)
  end

  def snapshot(value)
    Marshal.load(Marshal.dump(value))
  end

  describe "a one-click choice" do
    let(:previous) { process(no_material, catalog) }
    let(:line) { previous["lines"].first }
    let(:choice) { line["processing"]["question_choices"].find { |c| c["value"] == "stainless steel" } }
    let(:result) do
      described_class.apply(previous_result: previous, answers: [{ "line_id" => line["line_id"], "choice_id" => choice["id"] }], pipeline: pipeline)
    end
    let(:rerun) { result["lines"].first }

    it "starts as needs_buyer with material choices" do
      expect(line["state"]).to eq("needs_buyer")
      expect(line["processing"]["question_choices"].map { |c| c["field"] }.uniq).to eq(["material"])
      expect(choice["id"]).to eq("#{line['line_id']}-c3")
    end

    it "reruns the line into Ready with the stainless gauge thickness, the catalog item, and its price" do
      expect(rerun["state"]).to eq("ready")
      expect(rerun["spec"]["material"]).to eq("stainless steel")
      expect(rerun["spec"]["thickness"]).to eq(0.0625)
      expect(rerun["catalog_sku"]).to eq("RC-SS304-SHT-16GA-48X96-2B")
      expect(rerun["unit_price"]).to eq(2.5)
      expect(rerun["clarification_question"]).to be_nil
      expect(rerun["benchmark"]).to include("as_of")
    end

    it "keeps the line_id and position, and cites the buyer's choice as the material evidence" do
      expect(rerun["line_id"]).to eq(line["line_id"])
      expect(rerun["position"]).to eq(line["position"])
      expect(rerun["original_text"]).to eq(no_material)
      expect(rerun["evidence"]["material"]).to include("text" => choice["label"], "location" => "buyer answer")
      expect(rerun["evidence"]["material"]["explanation"]).to include(choice["id"], previous["revision"]["id"])
      expect(rerun["evidence"]["form"]["location"]).to start_with("line 1, chars")
    end

    it "records the answer and the run it came from on the line" do
      expect(rerun["processing"]["answered"]).to eq(
        "choice_id" => choice["id"], "free_text" => nil, "rfq_text" => nil, "previous_revision" => previous["revision"]["id"]
      )
    end

    it "issues a new revision, points back at the previous one, and names the changed line" do
      expect(result["revision"]["id"]).to match(/\Aproc-\d{8}-\d{6}-\h{8}\z/)
      expect(result["revision"]["id"]).not_to eq(previous["revision"]["id"])
      expect(result["revision"]["processor"]).to eq("rfq_processing #{RfqProcessing::VERSION} (answers)")
      expect(result["previous_revision"]).to eq(previous["revision"]["id"])
      expect(result["changed_line_ids"]).to eq([line["line_id"]])
      expect(result["schema_version"]).to eq(previous["schema_version"])
      expect(result["sample_data"]).to eq(previous["sample_data"])
      expect(result["source"]).to eq(previous["source"])
      expect(result["warnings"]).to eq([])
    end

    it "notes a stale revision_id but still applies the answer" do
      stale = described_class.apply(previous_result: previous, pipeline: pipeline,
                                    answers: [{ "line_id" => line["line_id"], "choice_id" => choice["id"], "revision_id" => "proc-20260101-000000-00000000" }])
      expect(stale["lines"].first["state"]).to eq("ready")
      expect(stale["warnings"].size).to eq(1)
      expect(stale["warnings"].first).to include("proc-20260101-000000-00000000", previous["revision"]["id"])
    end
  end

  describe "a two-line RFQ with one line answered" do
    let(:previous) { process("#{no_material}\n#{clean}", catalog) }
    let(:before) { snapshot(previous) }
    let(:choice) { previous["lines"].first["processing"]["question_choices"].find { |c| c["value"] == "stainless steel" } }
    let(:result) do
      before
      described_class.apply(previous_result: previous, answers: [{ "line_id" => previous["lines"].first["line_id"], "choice_id" => choice["id"] }],
                            pipeline: pipeline)
    end

    it "reruns line 1 only and copies line 2 unchanged" do
      expect(result["lines"].size).to eq(2)
      expect(result["lines"].first["state"]).to eq("ready")
      expect(result["lines"].last).to eq(before["lines"].last)
      expect(result["changed_line_ids"]).to eq([previous["lines"].first["line_id"]])
    end

    it "leaves the previous result untouched" do
      result
      expect(previous).to eq(before)
      expect(previous["lines"].first["state"]).to eq("needs_buyer")
    end
  end

  describe "a free-text answer for one line" do
    let(:previous) { process(no_material, catalog) }
    let(:line) { previous["lines"].first }
    let(:result) do
      described_class.apply(previous_result: previous, answers: [{ "line_id" => line["line_id"], "free_text" => "stainless 304 please" }], pipeline: pipeline)
    end
    let(:rerun) { result["lines"].first }

    it "reads the buyer's words without guessing a field" do
      expect(rerun["spec"]["material"]).to eq("stainless steel")
      expect(rerun["spec"]["grade"]).to eq("304")
      expect(rerun["spec"]["thickness"]).to eq(0.0625)
      expect(rerun["state"]).to eq("ready")
      expect(rerun["catalog_sku"]).to eq("RC-SS304-SHT-16GA-48X96-2B")
    end

    it "keeps the line_id and the RFQ words verbatim, and records what the buyer wrote" do
      expect(rerun["line_id"]).to eq(line["line_id"])
      expect(rerun["original_text"]).to eq(no_material)
      expect(rerun["processing"]["answered_with"]).to eq("stainless 304 please")
      expect(rerun["processing"]["answered"]).to eq(
        "choice_id" => nil, "free_text" => "stainless 304 please", "rfq_text" => nil, "previous_revision" => previous["revision"]["id"]
      )
      expect(result["changed_line_ids"]).to eq([line["line_id"]])
    end

    it "cites the buyer's words as the evidence and leaves RFQ evidence in place" do
      expect(rerun["evidence"]["material"]).to include("text" => "stainless", "location" => "buyer answer")
      expect(rerun["evidence"]["grade"]).to include("text" => "304", "location" => "buyer answer")
      expect(rerun["evidence"]["form"]["location"]).to start_with("line 1, chars")
    end

    it "warns when the words do not settle the question" do
      unsettled = described_class.apply(previous_result: previous, answers: [{ "line_id" => line["line_id"], "free_text" => "thanks" }], pipeline: pipeline)
      held = unsettled["lines"].first
      expect(held["state"]).to eq("needs_buyer")
      expect(held["line_id"]).to eq(line["line_id"])
      expect(held["processing"]["question_choices"].map { |c| c["id"] }).to eq(line["processing"]["question_choices"].map { |c| c["id"] })
      expect(unsettled["warnings"]).to eq(["line #{line['line_id']}: the buyer's answer did not settle the question; rep review needed"])
    end
  end

  describe "an answer that covers the whole RFQ" do
    let(:previous) { process("#{no_material}\n#{clean}", catalog) }
    let(:result) do
      described_class.apply(previous_result: previous, answers: [{ "scope" => "rfq", "free_text" => "all of it needs DFARS compliant material" }],
                            pipeline: pipeline)
    end

    it "reruns every line and every line now carries the DFARS flag" do
      expect(result["changed_line_ids"]).to eq(previous["lines"].map { |l| l["line_id"] })
      result["lines"].each do |line|
        expect(line["compliance"].map { |c| c["label"] }).to include("DFARS specialty metals clause")
        expect(line["processing"]["answered"]).to include("rfq_text" => "all of it needs DFARS compliant material", "previous_revision" => previous["revision"]["id"])
      end
    end

    it "keeps each line's identity and words, and does not settle a line question on its own" do
      expect(result["lines"].map { |l| l["line_id"] }).to eq(previous["lines"].map { |l| l["line_id"] })
      expect(result["lines"].map { |l| l["original_text"] }).to eq([no_material, clean])
      expect(result["lines"].first["state"]).to eq("needs_buyer")
      expect(result["lines"].last["state"]).to eq("ready")
    end

    it "applies a line choice and the whole-RFQ words together in one rerun" do
      choice = previous["lines"].first["processing"]["question_choices"].find { |c| c["value"] == "stainless steel" }
      both = described_class.apply(previous_result: previous, pipeline: pipeline,
                                   answers: [{ "line_id" => previous["lines"].first["line_id"], "choice_id" => choice["id"] },
                                             { "scope" => "rfq", "free_text" => "all of it needs DFARS compliant material" }])
      first = both["lines"].first
      expect(first["state"]).to eq("ready")
      expect(first["compliance"].map { |c| c["label"] }).to include("DFARS specialty metals clause")
      expect(first["processing"]["answered"]).to include("choice_id" => choice["id"], "rfq_text" => "all of it needs DFARS compliant material")
    end
  end

  describe "an answer that names nothing we know" do
    let(:previous) { process(no_material, catalog) }
    let(:before) { snapshot(previous) }
    let(:line_id) { previous["lines"].first["line_id"] }

    it "warns about an unknown choice_id and leaves the line unchanged" do
      before
      result = described_class.apply(previous_result: previous, answers: [{ "line_id" => line_id, "choice_id" => "#{line_id}-c99" }], pipeline: pipeline)
      expect(result["warnings"]).to eq(["line #{line_id}: unknown choice_id \"#{line_id}-c99\"; the answer was skipped"])
      expect(result["lines"]).to eq(before["lines"])
      expect(result["changed_line_ids"]).to eq([])
      expect(result["previous_revision"]).to eq(previous["revision"]["id"])
    end

    it "warns about an unknown line_id and an empty answer, and never raises" do
      result = described_class.apply(previous_result: previous, pipeline: pipeline,
                                     answers: [{ "line_id" => "line-9-deadbeef", "choice_id" => "line-9-deadbeef-c1" }, { "line_id" => line_id }, { "scope" => "rfq", "free_text" => "  " }])
      expect(result["warnings"]).to contain_exactly(
        "unknown line_id \"line-9-deadbeef\"; the answer was skipped",
        "line #{line_id}: the answer has neither a choice_id nor free_text; it was skipped",
        "a whole-RFQ answer has no text; it was skipped"
      )
      expect(result["changed_line_ids"]).to eq([])
    end
  end

  describe "a choice between two catalog items" do
    let(:other) { row.merge("pn" => "RC-SS304-SHT-16GA-48X96-4", "item_id" => "RC-SS304-SHT-16GA-48X96-4", "finish" => "#4", "description" => "304 sheet 16 ga 48x96 #4") }
    let(:catalog) { [row, other] }
    let(:previous) { process(clean, catalog) }
    let(:line) { previous["lines"].first }

    it "picks the chosen item and the line goes Ready with that catalog_sku" do
      expect(line["state"]).to eq("needs_buyer")
      choice = line["processing"]["question_choices"].find { |c| c["field"] == "catalog_item" && c["value"] == other["item_id"] }
      expect(choice).not_to be_nil
      result = described_class.apply(previous_result: previous, answers: [{ "line_id" => line["line_id"], "choice_id" => choice["id"] }], pipeline: pipeline)
      rerun = result["lines"].first
      expect(rerun["state"]).to eq("ready")
      expect(rerun["catalog_sku"]).to eq(other["item_id"])
      expect(rerun["line_id"]).to eq(line["line_id"])
      expect(rerun["processing"]["match"]["reason"]).to include("Chosen by the buyer's answer")
      expect(rerun["processing"]["answered"]["choice_id"]).to eq(choice["id"])
    end
  end
end
