require "test_helper"

# The shape RFQ processing expects (docs/rfq_processing/RESULT-FORMAT.md).
class CatalogMatch::ContractTest < ActiveSupport::TestCase
  def call(input) = CatalogMatch::Contract.call(input)

  test "an exact part number is status exact with score 1.0" do
    result = call("line_text" => "AN3-13A bolts, 100 ea, need C of C",
                  "spec" => { "part_number" => "AN3-13A" }, "quantity" => 100, "quantity_unit" => "each")
    assert_equal "exact", result["status"]
    assert_equal 0.8, result["threshold"]
    assert_equal "AVI-001", result["best"]["item_id"]
    assert_equal "AN3-13A", result["best"]["part_number"]
    assert_equal 1.0, result["best"]["score"]
    assert_equal [], result["candidates"]
  end

  test "a clear description is scored with the reasons it matched" do
    result = call("line_text" => "40,000 lb S-330 steel shot")
    assert_equal "scored", result["status"]
    assert_equal "RC-STEELSHOT-S330", result["best"]["part_number"]
    assert_includes result["best"]["matched_on"], "grade: \"S-330\""
    assert_empty result["best"]["mismatches"]
  end

  test "two fitting items are ambiguous, with no best and a question" do
    result = call("line_text" => "304 SS sheet 16ga 4x8")
    assert_equal "ambiguous", result["status"]
    assert_nil result["best"]
    assert_equal 2, result["candidates"].size
    assert_match(/2B or #4/, result["question"])
  end

  test "nothing that fits is no_match, with the closest listed separately" do
    result = call("line_text" => "Stainless Steel Sheet 304 1/16 in 16 Ga 2B 12 in x 12 in")
    assert_equal "no_match", result["status"]
    assert_nil result["best"]
    assert result["closest"].any?
  end

  test "a normalized spec from processing fills what the text left out" do
    result = call("line_text" => "16 ga sheet 4x8", "spec" => { "material" => "galvanized steel" })
    assert_equal "scored", result["status"]
    assert_equal "RC-GV-SHT-16GA-48X96", result["best"]["part_number"]
  end

  test "the text beats the normalized spec" do
    result = call("line_text" => "14 ga 5052 alum 4x8", "spec" => { "material" => "stainless steel" })
    assert_equal "RC-AL5052-SHT-14GA-48X96", result["best"]["part_number"]
  end

  test "the command reads JSON on stdin and writes JSON on stdout" do
    output = IO.popen([ RbConfig.ruby, Rails.root.join("bin/catalog-match").to_s ], "r+") do |io|
      io.write({ line_text: "P1020A sow" }.to_json)
      io.close_write
      io.read
    end
    assert_equal "RC-AL-P1020-SOW", JSON.parse(output).dig("best", "part_number")
  end
end
