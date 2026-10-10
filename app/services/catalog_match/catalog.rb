module CatalogMatch
  # Read-only access to the sample catalogs in data/. Items are plain hashes
  # with string keys, exactly as stored in the JSON files.
  class Catalog
    CATALOG_FILES = {
      "metals" => Rails.root.join("data/metals/catalog.json"),
      "rudco" => Rails.root.join("data/rudco/catalog.json"),
      "aviation" => Rails.root.join("data/aviation/catalog.json")
    }.freeze

    def self.default
      @default ||= new(CATALOG_FILES.keys)
    end

    def self.reset!
      @default = nil
    end

    attr_reader :items

    def initialize(catalog_names = CATALOG_FILES.keys, items: nil)
      @items = items || catalog_names.flat_map { |name| load_catalog(name) }
      @by_pn = @items.index_by { |entry| entry["pn"].upcase }
    end

    def find(pn)
      @by_pn[pn.to_s.strip.upcase]
    end

    def part_numbers
      @by_pn.keys
    end

    private

    # The aviation file names its part number "part_number" and uses its own
    # field names; map the fields the matcher reads onto the shared names.
    def load_catalog(name)
      JSON.parse(File.read(CATALOG_FILES.fetch(name))).map do |entry|
        next entry.merge("catalog" => name) if entry.key?("pn")

        entry.merge(
          "catalog" => name,
          "pn" => entry["part_number"],
          "form" => "bolt",
          "description" => entry["normalized_description"],
          "unit" => entry["purchase_unit"],
          "standard" => entry["standard_designation"]
        )
      end
    end
  end
end
