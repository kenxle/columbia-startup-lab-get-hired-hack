require "test_helper"

# Lines and expected readings come from the test set in
# docs/research/20261010.01_rfq_sharper_angle/research_domain_rules.md, section 6.
class CatalogMatch::MatcherTest < ActiveSupport::TestCase
  def match(text) = CatalogMatch::Matcher.call(text)

  def assert_matches_item(text, pn)
    result = match(text)
    assert_equal "match", result.outcome, "#{text}: #{result.question}"
    assert_equal pn, result.best.item["pn"]
  end

  def assert_question(text, pattern, includes: [])
    result = match(text)
    assert_equal "candidates", result.outcome, text
    assert_match pattern, result.question
    includes.each { |pn| assert_includes result.candidates.map { |candidate| candidate.item["pn"] }, pn }
    result
  end

  test "clear lines match one stocked item" do
    assert_matches_item "16 ga galv 4x10 x 25", "RC-GV-SHT-16GA-48X120"
    assert_matches_item "14 ga 5052 alum 4x8 x10", "RC-AL5052-SHT-14GA-48X96"
    assert_matches_item "3/16 304 plt 4x8 x4", "RC-SS304-PLT-188-48X96"
    assert_matches_item "SA-240 316L 3/8 plt 60x120 x2 w/ 3.1 cert", "RC-SS316-PLT-375-60X120"
    assert_matches_item "2in sch40 304/304L A312 smls 20ft x30 PMI", "RC-SS304-PIPE-2000-S40-SMLS-20FT"
    assert_matches_item "304 rd bar 2in A276 12ft x10", "RC-SS304-RND-2000-12FT"
    assert_matches_item "6061-T651 plate 2 x 12 x 24 x4", "RC-AL6061-PLT-2000-12X24"
    assert_matches_item "L3x3x1/4 x 20' A36 galv x40 Buy America state DOT bridge", "RC-A36G-ANG-3000X3000-250-20FT"
    assert_matches_item "Stainless Steel Sheets Type 304-2B Stainless Sheets 4 x 10 48\" x 120\" long x 16 Gauge",
                        "RC-SS304-SHT-16GA-48X120-2B"
  end

  test "a gauge on tube uses the tube wall table, and asks nothing (T25 negative control)" do
    result = match("1-1/2 sq tube A500 C 11ga 24ft x8")
    assert_equal "match", result.outcome
    assert_equal "RC-A500-SQT-1500-120-24FT", result.best.item["pn"]
    assert_nil result.question
  end

  test "feet are converted for sheet and plate sizes" do
    assert_matches_item "ASTM A36 or A572 Gr. 50 equivalent hot-rolled carbon steel 8 feet x 20 feet x 1 inch thick",
                        "RC-A36-PLT-1000-96X240"
    reading = match("304 SS sheet 16ga 4x8").reading
    assert_equal [ 48.0, 96.0 ], [ reading["width"], reading["length"] ]
  end

  test "a missing finish becomes a choice between the stocked finishes (T10)" do
    assert_question "304 SS sheet 16ga 4x8", /finish.*2B or #4/,
                    includes: %w[RC-SS304-SHT-16GA-48X96-2B RC-SS304-SHT-16GA-48X96-4]
  end

  test "0.060 in stainless is the gauge trap, so it asks (T11)" do
    result = assert_question "Stainless 304, 0.060 in, 48 x 96", /0\.060 in.*16 ga \(0\.0625 in\)/
    assert_nil result.reading["quantity"], "48 x 96 is a size, not a count"
  end

  test "a missing material asks which material (T12)" do
    result = assert_question "16 ga sheet 4x8 qty 20", /material/
    assert_equal 20, result.reading["quantity"]
    materials = result.candidates.map { |candidate| candidate.item["material"] }.uniq
    assert_operator materials.size, :>=, 3
  end

  test "two specs on one line ask which governs (T3)" do
    assert_question "Square Tube A513-A500 Grade B 2\" x 2\" x 24' long x .188 thick", /A513 and A500/
  end

  test "a spec we do not stock asks before substituting (T19)" do
    assert_question "2x2 sq tube A53 Gr B .120 24ft", /A53/
  end

  test "nothing in stock is no match, never forced onto the closest item" do
    result = match("Stainless Steel Sheet 304 1/16 in 16 Ga 2B 12 in x 12 in")
    assert_equal "no_match", result.outcome
    assert_empty result.candidates
    assert result.closest.any?
  end

  test "a line with no product words asks for one" do
    result = match("please call me")
    assert_equal "no_match", result.outcome
    assert_match(/material, form and size/, result.question)
  end

  test "part numbers match exactly, including our own PN" do
    assert_matches_item "need 25 an3-13a", "AN3-13A"
    assert_matches_item "RC-SS304-PLT-250-48X96 x3", "RC-SS304-PLT-250-48X96"
  end

  test "a part number we do not stock offers its drilled or undrilled variant" do
    result = match("AN3-13")
    assert_equal "candidates", result.outcome
    assert_equal [ "AN3-13A" ], result.candidates.map { |candidate| candidate.item["pn"] }
    assert_match(/AN3-13 is not in our catalog/, result.question)
  end

  test "aviation hardware keeps its real form, and MS and nut part numbers are read" do
    catalog = CatalogMatch::Catalog.default
    nut = catalog.items.find { |item| item["pn"] == "AN315-3L" }
    assert_equal "plain hex nut", nut["form"]
    assert_matches_item "AN315-3L nuts x 50", "AN315-3L"
    screw = catalog.items.find { |item| item["form"] == "machine screw" }
    assert_matches_item "need #{screw['pn'].downcase}", screw["pn"]
  end

  test "questions talk about the catalog, never claim stock" do
    [ "AN3-13", "Stainless 304, 0.060 in, 48 x 96", "2x2 sq tube A53 Gr B .120 24ft", "please call me" ].each do |text|
      assert_no_match(/\bstock/i, match(text).question.to_s, text)
    end
  end

  test "bolts can be found from words" do
    assert_matches_item "3/16 cad bolt 1 inch grip undrilled", "AN3-13A"
  end

  test "RudCo abrasives and aluminum ingot match from their usual names" do
    assert_matches_item "40,000 lb S-330 steel shot", "RC-STEELSHOT-S330"
    assert_matches_item "S330 shot 20 bags", "RC-STEELSHOT-S330"
    assert_matches_item "steel grit G-25 x 10 tons", "RC-STEELGRIT-G25"
    assert_matches_item "P1020 aluminum ingot 44,000 lbs", "RC-AL-P1020-TBARINGOT"
    assert_matches_item "P1020A sow", "RC-AL-P1020-SOW"
    assert_matches_item "aluminum 356 ingot", "RC-AL-356-NOTCHEDINGOT"
    assert_matches_item "A356.2 notched ingot 2 pallets", "RC-AL-A356-NOTCHEDINGOT"
    assert_matches_item "36 grit aluminum oxide 50 bags", "RC-ALUMINUMOXIDE-36GRIT"
  end

  test "bulk quantities keep their unit" do
    reading = match("40,000 lb S-330 steel shot").reading
    assert_equal 40_000, reading["quantity"]
    assert_equal "lb", reading["quantity_unit"]
  end

  test "RudCo lines that leave out the form or alloy ask for it" do
    assert_question "P1020", /form.*sow or ingot/
    assert_question "stainless S-330 2,000 lb", /S-330 \(304\) or S-330 \(410\)/
  end

  test "a galvanized coating is never read as a grit size" do
    reading = match("G90 galv sheet 16ga 4x8").reading
    assert_equal "galvanized steel", reading["material"]
    assert_nil reading["grade"]
  end

  test "every check quotes the buyer's words" do
    match("304 SS sheet 16ga 4x8").candidates.each do |candidate|
      candidate.checks.each { |check| assert check[:buyer_text].present?, check.inspect }
    end
  end
end

class CatalogMatch::MatcherPartNumberGuardTest < ActiveSupport::TestCase
  test "a part number does not override what else the buyer wrote" do
    result = CatalogMatch::Matcher.call("RC-SS304-SHT-16GA-48X96-2B #4 finish")
    assert_equal "candidates", result.outcome
    assert_match(/#4|finish/, result.question)

    assert_equal "match", CatalogMatch::Matcher.call("RC-SS304-SHT-16GA-48X96-2B 304 sheet 2B").outcome
  end
end

class CatalogMatch::MatcherShorthandTest < ActiveSupport::TestCase
  test "A-572 G50 is a plate grade, not steel grit (Ken 14:36)" do
    reading = CatalogMatch::Matcher.call("1/2 A-572 G50 plate 48x96 x2").reading
    assert_equal "A572-50", reading["grade"]
    assert_equal "carbon steel", reading["material"]
    assert_equal "plate", reading["form"]
  end

  test "glass bead #4 is a bead size, not a No. 4 finish (Ken 14:36)" do
    result = CatalogMatch::Matcher.call("glass bead #4, 10 bags")
    assert_equal "match", result.outcome
    assert_equal "RC-GLASSBEADS-4", result.best.item["pn"]
    assert_nil result.reading["finish"]
  end

test "a confirmed reading with provenance resolves the gauge trap; a plain number never overrides (Yuval 15:08)" do
  line = "Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets"
  confirmed = CatalogMatch::Contract.call({ "line_text" => line,
                                            "spec" => { "thickness" => { "value" => 0.0625, "confirmed_on" => "RFQ-0015", "term" => "0.060 in" } } })
  assert_equal "scored", confirmed["status"]
  assert_equal "RC-SS304-SHT-16GA-48X96-2B", confirmed["best"]["part_number"]
  assert_equal 1.0, confirmed["best"]["score"]

  untaught = CatalogMatch::Contract.call({ "line_text" => line, "spec" => { "thickness" => 0.0625 } })
  assert_equal "ambiguous", untaught["status"], "an untaught 0.0625 must preserve the explicit 0.060"

  quantity = CatalogMatch::Matcher.call("S-330 steel shot, 100 lb", given: { "quantity" => { "value" => 104, "confirmed_on" => "RFQ-0001" } })
  assert_equal 100, quantity.reading["quantity"], "a quantity is never overridden"

  other_words = CatalogMatch::Contract.call({ "line_text" => "Stainless 304, 0.125 in, 48 x 96, 2B",
                                              "spec" => { "thickness" => { "value" => 0.0625, "term" => "0.060 in" } } })
  assert_not_equal "RC-SS304-SHT-16GA-48X96-2B", other_words.dig("best", "part_number")
end
end
