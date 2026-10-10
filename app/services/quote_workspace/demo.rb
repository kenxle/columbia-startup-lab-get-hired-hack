module QuoteWorkspace
  # Creates one fixed, synthetic RFQ with three known lines for this browser
  # session. It does not parse anything. Catalog items and prices are sample
  # data and are labeled that way.
  class Demo
    BUYER_NAME = "Northline Fabrication".freeze
    TITLE = "Sheet and plate sourcing".freeze
    SAMPLE_PRICE_SOURCE = "Sample price table (not live market data)".freeze

    SOURCE_TEXT = <<~TEXT.freeze
      From: Purchasing, Northline Fabrication
      Subject: RFQ for sheet and plate

      Hello,

      Please quote the following:

      1. 304 SS sheet 16ga 4x8, ASTM A240, 2B finish, qty 20
      2. Plate 1/4 x 48 x 96, qty 10
      3. 7075-T6 aluminum sheet .125 x 48 x 144, qty 2

      MTRs required on all stainless.

      Thanks,
      Purchasing, Northline Fabrication
    TEXT

    ITEM_ONE = "1. 304 SS sheet 16ga 4x8, ASTM A240, 2B finish, qty 20".freeze
    ITEM_TWO = "2. Plate 1/4 x 48 x 96, qty 10".freeze
    ITEM_THREE = "3. 7075-T6 aluminum sheet .125 x 48 x 144, qty 2".freeze

    def self.create!(workspace_token:)
      Quote.transaction do
        quote = Quote.create!(
          title: TITLE,
          buyer_name: BUYER_NAME,
          source_text: SOURCE_TEXT,
          workspace_token: workspace_token,
          sample_data: true
        )
        ApplyResult.call(quote: quote, result: result)
      end
    end

    def self.result
      {
        "schema_version" => 1,
        "sample_data" => true,
        "lines" => [ ready_line, missing_material_line, no_match_line ]
      }
    end

    def self.evidence(text, location, explanation)
      { "text" => text, "location" => location, "explanation" => explanation }
    end

    def self.ready_line
      location = "RFQ email, item 1"
      {
        "position" => 1,
        "description" => "304 stainless steel sheet, 16 gauge, 48 x 96 in, ASTM A240, 2B finish",
        "original_text" => ITEM_ONE,
        "spec" => {
          "material" => "Stainless steel",
          "grade" => "304",
          "form" => "Sheet",
          "thickness" => "16 gauge",
          "width" => "48 in",
          "length" => "96 in",
          "standard" => "ASTM A240",
          "finish" => "2B"
        },
        "quantity" => "20",
        "quantity_unit" => "sheet",
        "catalog_sku" => "SAMPLE-SS304-16GA-48X96-2B",
        "unit_price" => "232.00",
        "price_source" => SAMPLE_PRICE_SOURCE,
        "state" => "ready",
        "clarification_question" => nil,
        "notes" => nil,
        "evidence" => {
          "material" => evidence("SS", location, "SS is common shorthand for stainless steel."),
          "grade" => evidence("304", location, "Grade written by the buyer."),
          "form" => evidence("sheet", location, "Form written by the buyer."),
          "thickness" => evidence("16ga", location, "Gauge written by the buyer. The sample catalog item is listed by the same gauge."),
          "width" => evidence("4x8", location, "4 x 8 read as feet, the 48 x 96 in sheet size."),
          "length" => evidence("4x8", location, "4 x 8 read as feet, the 48 x 96 in sheet size."),
          "standard" => evidence("ASTM A240", location, "Standard written by the buyer."),
          "finish" => evidence("2B finish", location, "Finish written by the buyer."),
          "quantity" => evidence("qty 20", location, "Quantity written by the buyer, read as sheets.")
        },
        "compliance" => [
          {
            "label" => "Mill test report",
            "evidence" => "MTRs required on all stainless.",
            "note" => "Requested by the buyer for stainless lines. This records the request, not a certification of stock."
          }
        ],
        "benchmark" => {
          "name" => "Sample price table",
          "as_of" => "2026-10-10",
          "unit" => "USD per sheet",
          "kind" => "sample",
          "explanation" => "Sample price built for this demo. It is not live market data."
        },
        "unresolved_fields" => []
      }
    end

    def self.missing_material_line
      location = "RFQ email, item 2"
      {
        "position" => 2,
        "description" => "Plate, 1/4 in x 48 x 96 in, material not stated",
        "original_text" => ITEM_TWO,
        "spec" => {
          "form" => "Plate",
          "thickness" => "0.25 in",
          "width" => "48 in",
          "length" => "96 in"
        },
        "quantity" => "10",
        "quantity_unit" => "plate",
        "catalog_sku" => nil,
        "unit_price" => nil,
        "price_source" => nil,
        "state" => "needs_buyer",
        "clarification_question" =>
          "Item 2 asks for 1/4 x 48 x 96 in plate but does not name a material or grade. Which material and grade do you need?",
        "notes" => nil,
        "evidence" => {
          "form" => evidence("Plate", location, "Form written by the buyer."),
          "thickness" => evidence("1/4", location, "First dimension read as thickness in inches."),
          "width" => evidence("48", location, "Second dimension read as width in inches."),
          "length" => evidence("96", location, "Third dimension read as length in inches."),
          "quantity" => evidence("qty 10", location, "Quantity written by the buyer.")
        },
        "compliance" => [],
        "benchmark" => nil,
        "unresolved_fields" => [ "material", "grade" ]
      }
    end

    def self.no_match_line
      location = "RFQ email, item 3"
      {
        "position" => 3,
        "description" => "7075-T6 aluminum sheet, 0.125 x 48 x 144 in",
        "original_text" => ITEM_THREE,
        "spec" => {
          "material" => "Aluminum",
          "grade" => "7075-T6",
          "form" => "Sheet",
          "thickness" => "0.125 in",
          "width" => "48 in",
          "length" => "144 in"
        },
        "quantity" => "2",
        "quantity_unit" => "sheet",
        "catalog_sku" => nil,
        "unit_price" => nil,
        "price_source" => nil,
        "state" => "no_match",
        "clarification_question" =>
          "Item 3, 7075-T6 aluminum sheet 0.125 x 48 x 144 in, does not match an item in our sample catalog. Is a different size or alloy acceptable?",
        "notes" => nil,
        "evidence" => {
          "material" => evidence("aluminum", location, "Material written by the buyer."),
          "grade" => evidence("7075-T6", location, "Alloy and temper written by the buyer."),
          "form" => evidence("sheet", location, "Form written by the buyer."),
          "thickness" => evidence(".125", location, "First dimension read as thickness in inches."),
          "width" => evidence("48", location, "Second dimension read as width in inches."),
          "length" => evidence("144", location, "Third dimension read as length in inches."),
          "quantity" => evidence("qty 2", location, "Quantity written by the buyer.")
        },
        "compliance" => [],
        "benchmark" => nil,
        "unresolved_fields" => []
      }
    end

    private_class_method :evidence, :ready_line, :missing_material_line, :no_match_line
  end
end
