# frozen_string_literal: true

module RfqProcessing
  # Gauge to thickness in inches, keyed by material family and form.
  # A gauge number is not a thickness: each material family has its own table,
  # and tube wall has a table of its own. Values are nominal. Source: Ken's
  # domain research, section 1.1 (Metal Supermarkets sheet metal gauge chart;
  # tube wall from Wikipedia, Sheet metal). Only researched gauges are listed;
  # anything else returns nil so the line becomes a question, not a guess.
  module GaugeTable
    SOURCE = "Metal Supermarkets sheet metal gauge chart (tube wall: Wikipedia, Sheet metal)"

    TABLES = {
      "mild steel" => { 10 => 0.1345, 11 => 0.1196, 12 => 0.1046, 14 => 0.0747, 16 => 0.0598, 18 => 0.0478, 20 => 0.0359 },
      "galvanized steel" => { 10 => 0.1382, 11 => 0.1233, 12 => 0.1084, 14 => 0.0785, 16 => 0.0635, 18 => 0.0516, 20 => 0.0396 },
      "stainless steel" => { 10 => 0.14062, 11 => 0.125, 12 => 0.10937, 14 => 0.07812, 16 => 0.0625, 18 => 0.050, 20 => 0.0375 },
      "aluminum" => { 10 => 0.1019, 11 => 0.09074, 12 => 0.08081, 14 => 0.06408, 16 => 0.05082, 18 => 0.04030, 20 => 0.03196 },
      "steel tube wall" => { 10 => 0.134, 11 => 0.120, 12 => 0.109, 14 => 0.083, 16 => 0.065, 18 => 0.049, 20 => 0.035 }
    }.freeze

    # Aluminum 14 gauge differs between published charts (0.06408 vs 0.063).
    ALTERNATIVES = {
      ["aluminum", 14] => { value: 0.063, source: "Wikipedia, Sheet metal" }
    }.freeze

    TUBE_FORMS = %w[tube square\ tube rectangular\ tube round\ tube].freeze

    Lookup = Struct.new(:thickness_in, :table, :source, :alternative, keyword_init: true)

    # Returns a Lookup, or nil when no researched table covers the case.
    def self.lookup(gauge:, material:, form: nil)
      return nil unless gauge.is_a?(Integer)

      table = table_for(material: material, form: form)
      return nil unless table

      value = TABLES[table][gauge]
      return nil unless value

      Lookup.new(thickness_in: value, table: table, source: SOURCE, alternative: ALTERNATIVES[[table, gauge]])
    end

    # All candidate readings when the material is unknown. Used to word the question.
    def self.candidates(gauge:, form: nil)
      tables = TUBE_FORMS.include?(form.to_s) ? ["steel tube wall"] : TABLES.keys - ["steel tube wall"]
      tables.filter_map do |table|
        value = TABLES[table][gauge]
        value && { table: table, thickness_in: value }
      end
    end

    def self.table_for(material:, form:)
      return "steel tube wall" if TUBE_FORMS.include?(form.to_s) && material.to_s != "aluminum"

      case material.to_s
      when "stainless steel" then "stainless steel"
      when "galvanized steel" then "galvanized steel"
      when "aluminum" then "aluminum"
      when "carbon steel", "mild steel", "steel" then "mild steel"
      end
    end
  end
end
