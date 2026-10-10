# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "catalog_reader"

class CatalogReaderTest < Minitest::Test
  DATA_DIRECTORY = File.expand_path("../../data/aviation", __dir__)

  def setup
    @reader = RfqCatalog::Reader.new(DATA_DIRECTORY)
  end

  def test_complete_price_coverage
    assert @reader.validate!
    assert_equal 500, @reader.items.length
    assert_equal 1000, @reader.observations.length
  end

  def test_original_item_ids_and_parts_are_preserved
    historical = File.read(File.expand_path("../../docs/data/AVIATION_ITEMS_200.md", __dir__))
    original = historical.scan(/^\| (AVI-\d{3}) \| ([^|]+) \|/).to_h
    assert_equal 200, original.length
    original.each { |id, part| assert_equal id, @reader.find(part.strip).fetch("item_id") }
  end

  def test_decimal_prices_and_case_normalization
    reference = @reader.price_reference(" an3-13a ")
    assert_equal BigDecimal("0.55"), reference[:minimum]
    assert_equal BigDecimal("0.58"), reference[:maximum]
    assert_equal BigDecimal("0.565"), reference[:midpoint]
    assert_equal false, reference[:quote_ready]
    assert_nil reference[:suggested_selling_price]
  end

  def test_missing_specifications_stay_visible
    item = @reader.items.find { |i| !i.dig("specification_verification", "dimensions_verified") }
    reference = @reader.price_reference(item.fetch("part_number"))
    refute reference[:dimensions_verified]
    refute_empty reference[:specification_gaps]
    assert_equal 2, reference[:sources].length
    assert_equal false, reference[:quote_ready]
  end

  def test_unknown_part_does_not_receive_an_invented_price
    assert_nil @reader.find("DOES-NOT-EXIST")
    assert_nil @reader.price_reference("DOES-NOT-EXIST")
    assert_empty @reader.offers_for("DOES-NOT-EXIST")
  end

  def test_duplicate_part_is_rejected
    @reader.items.last["part_number"] = @reader.items.first.fetch("part_number")
    # Reloaded indexes must detect duplicates as they would during import.
    with_modified_catalog(@reader.items) do |directory|
      assert_raises(RfqCatalog::InvalidCatalog) { RfqCatalog::Reader.new(directory).validate! }
    end
  end

  def test_forged_quote_readiness_is_rejected
    @reader.items.first["quote_ready"] = true
    assert_raises(RfqCatalog::InvalidCatalog) { @reader.validate! }
  end

  def test_pack_price_cannot_be_compared_as_a_piece
    @reader.observations.first["pack_quantity"] = 25
    assert_raises(RfqCatalog::InvalidCatalog) { @reader.validate! }
  end

  def test_undocumented_supplier_alias_is_rejected
    @reader.observations.first["supplier_part_number"] = "OTHER-PART"
    assert_raises(RfqCatalog::InvalidCatalog) { @reader.validate! }
  end

  private

  def with_modified_catalog(items)
    Dir.mktmpdir("rfq-catalog-test") do |directory|
      %w[price_observations.json source_manifest.json summary.json].each do |name|
        File.write(File.join(directory, name), File.read(File.join(DATA_DIRECTORY, name)))
      end
      File.write(File.join(directory, "catalog.json"), JSON.generate(items))
      yield directory
    end
  end
end
