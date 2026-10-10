require "test_helper"

class QuoteLineTest < ActiveSupport::TestCase
  setup do
    @quote = QuoteWorkspace::Demo.create!(workspace_token: "quote-line-model-test-workspace")
    @ready_line = @quote.quote_lines.first
    @held_line = @quote.quote_lines.second
    @no_match_line = @quote.quote_lines.third
  end

  test "status labels use the product brief wording" do
    assert_equal "Ready", @ready_line.status_label
    assert_equal "Question to send", @held_line.status_label
    assert_equal "No match", @no_match_line.status_label
  end

  test "quantity must be a positive number" do
    [ "abc", "0", "-1", "12abc" ].each do |bad_quantity|
      @held_line.quantity = bad_quantity
      refute @held_line.valid?, "expected quantity #{bad_quantity.inspect} to be invalid"
      assert @held_line.errors[:quantity].any?
    end

    @held_line.quantity = "12.5"
    assert @held_line.valid?
  end

  test "unit price must be a nonnegative number" do
    [ "abc", "-0.01", "1,000" ].each do |bad_price|
      @ready_line.unit_price = bad_price
      refute @ready_line.valid?, "expected unit price #{bad_price.inspect} to be invalid"
      assert @ready_line.errors[:unit_price].any?
    end

    @ready_line.unit_price = "0"
    assert @ready_line.valid?
  end

  test "a missing price is allowed only on held lines" do
    @held_line.unit_price = nil
    assert @held_line.valid?

    @ready_line.unit_price = nil
    refute @ready_line.valid?
    assert @ready_line.errors[:unit_price].any?
  end

  test "a ready line needs a catalog SKU, a price source and no unresolved fields" do
    @ready_line.catalog_sku = nil
    refute @ready_line.valid?

    @ready_line.reload
    @ready_line.price_source = ""
    refute @ready_line.valid?

    @ready_line.reload
    @ready_line.unresolved_fields = [ "grade" ]
    refute @ready_line.valid?
    refute @ready_line.quotable?
  end

  test "a no match line cannot name a catalog SKU" do
    @no_match_line.catalog_sku = "SAMPLE-ANY"

    refute @no_match_line.valid?
    assert @no_match_line.errors[:catalog_sku].any?
  end

  test "spec rejects unknown fields and evidence must quote source text" do
    @ready_line.spec = @ready_line.spec.merge("color" => "red")
    refute @ready_line.valid?
    assert @ready_line.errors[:spec].any?

    @ready_line.reload
    @ready_line.evidence = @ready_line.evidence.merge("grade" => { "text" => "", "location" => "item 1" })
    refute @ready_line.valid?
    assert @ready_line.errors[:evidence].any?
  end

  test "editing a spec field sends the line back for reprocessing" do
    assert @ready_line.apply_manual_edit("spec" => { "material" => "Carbon steel" })

    @ready_line.reload
    assert_equal "needs_buyer", @ready_line.state
    assert_equal "Carbon steel", @ready_line.spec_value("material")
    assert_includes @ready_line.edited_fields, "material"
    assert @ready_line.clarification_question.present?
    refute @ready_line.quotable?
    assert_equal "SAMPLE-SS304-16GA-48X96-2B", @ready_line.catalog_sku, "an edit must not invent or clear a match"
    assert_equal BigDecimal("0"), @quote.reload.subtotal
    refute @quote.approvable?
  end

  test "editing the quantity sends the line back for reprocessing" do
    assert @ready_line.apply_manual_edit("quantity" => "25")

    @ready_line.reload
    assert_equal "needs_buyer", @ready_line.state
    assert_includes @ready_line.edited_fields, "quantity"
  end

  test "an existing question is kept when a spec field changes" do
    original_question = @held_line.clarification_question
    assert @held_line.apply_manual_edit("spec" => { "thickness" => "0.250 in" })

    assert_equal original_question, @held_line.reload.clarification_question
  end

  test "a price edit keeps a ready line ready and labels the price as rep-entered" do
    assert @ready_line.apply_manual_edit("unit_price" => "250")

    @ready_line.reload
    assert_equal "ready", @ready_line.state
    assert @ready_line.rep_entered_price?
    assert_includes @ready_line.edited_fields, "unit_price"
    assert_equal BigDecimal("5000.00"), @quote.reload.subtotal
  end

  test "a rejected edit is not saved and keeps approval" do
    @quote.approve!

    refute @ready_line.apply_manual_edit("quantity" => "abc")
    assert @ready_line.errors[:quantity].any?

    @ready_line.reload
    assert_equal BigDecimal("20"), @ready_line.quantity
    assert_equal "ready", @ready_line.state
    assert @quote.reload.approved?
  end

  test "clearing the price on a ready line is rejected" do
    refute @ready_line.apply_manual_edit("unit_price" => "")
    assert @ready_line.errors[:unit_price].any?
    assert_equal BigDecimal("232.00"), @ready_line.reload.unit_price
  end

  test "manual edits cannot change state, catalog SKU or evidence" do
    assert @held_line.apply_manual_edit(
      "state" => "ready",
      "catalog_sku" => "SAMPLE-INVENTED",
      "evidence" => {},
      "notes" => "Buyer called about this line."
    )

    @held_line.reload
    assert_equal "needs_buyer", @held_line.state
    assert_nil @held_line.catalog_sku
    assert @held_line.evidence.key?("thickness")
    assert_equal "Buyer called about this line.", @held_line.notes
  end

  test "an edit leaves unresolved fields and compliance in place" do
    assert @ready_line.apply_manual_edit("description" => "Edited description")

    @ready_line.reload
    assert_equal "Mill test report", @ready_line.compliance.first["label"]
    assert_equal [ "material", "grade" ], @held_line.reload.unresolved_fields
  end

  test "display description falls back to the original text" do
    @held_line.description = nil

    assert_equal "2. Plate 1/4 x 48 x 96, qty 10", @held_line.display_description
  end
end
