# frozen_string_literal: true

RSpec.describe RfqProcessing::ResultBuilder do
  rudco_row = { "pn" => "RC-STEELSHOT-S330", "item_id" => "RC-STEELSHOT-S330", "form" => "abrasive", "material" => "steel shot", "grade" => "S-330",
                "description" => "Steel Shot S-330", "unit" => "lb", "list_price_usd_per_lb" => 0.4,
                "list_price_source" => { "url" => "https://www.rud-co.com/abrasives/steel-shot", "kind" => "RudCo website list price", "text" => "$0.40/lb" } }
  metals_row = { "pn" => "RC-A36-PLT-500-60X120", "item_id" => "RC-A36-PLT-500-60X120", "form" => "plate", "material" => "carbon steel", "grade" => "A36",
                 "thickness_in" => 0.5, "width_in" => 60, "length_in" => 120, "description" => "A36 plate 1/2 in 60 x 120" }

  it "prices a RudCo item from its labeled website list price" do
    result = RfqProcessing.process(content: "Steel shot S-330, 2,000 lb, COA with each lot", type: "email", catalog: [rudco_row])
    line = result["lines"].first
    expect(line["state"]).to eq("ready")
    expect(line["unit_price"]).to eq(0.4)
    expect(line["price_source"]).to include("RudCo website list price")
    expect(line["benchmark"]["kind"]).to eq("sample")
    expect(line["compliance"].map { |c| c["label"] }).to include("Certificate of analysis (COA) required")
  end

  it "holds a matched line with no price instead of calling it Ready" do
    result = RfqProcessing.process(content: "1/2 A36 PL 5x10 x3", type: "email", catalog: [metals_row])
    line = result["lines"].first
    expect(line["state"]).to eq("needs_buyer")
    expect(line["catalog_sku"]).to eq("RC-A36-PLT-500-60X120")
    expect(line["unresolved_fields"]).to eq(["unit_price"])
    expect(line["clarification_question"]).to include("matched to RC-A36-PLT-500-60X120")
  end
end
