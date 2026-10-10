# frozen_string_literal: true

module RfqProcessing
  # The words buyers use, mapped to normalized values. Every pattern returns the
  # exact matched text as evidence. Order matters: more specific first.
  # Sources: Ken's domain research sections 1.3 to 2 (grades, finishes, forms, specs).
  module Lexicon
    MATERIALS = [
      # RudCo's own products first (abrasives), so "steel shot" is not read as carbon steel
      [/\bsteel\s*shot\b/i, "steel shot", "steel shot is a blasting abrasive, sold by weight"],
      [/\bsteel\s*grit\b/i, "steel grit", "steel grit is a blasting abrasive, sold by weight"],
      [/\balumin\w*\s*oxide\b/i, "aluminum oxide", "aluminum oxide is a blasting abrasive, sold by weight"],
      [/\bgarnet\b/i, "garnet", "garnet is a blasting abrasive, sold by weight"],
      [/\bglass\s*beads?\b/i, "glass bead", "glass bead is a blasting media, sold by weight"],
      [/\bstainless\b/i, "stainless steel", "stainless means stainless steel"],
      [/\bS\.?S\.?(?=[\s,.;]|$)/, "stainless steel", "SS is the common abbreviation for stainless steel"],
      [/\bgalv(?:anized|anised|\.)?\b/i, "galvanized steel", "galv means galvanized steel, which has its own gauge table"],
      [/\balum(?:inum|inium|\.)?\b/i, "aluminum", "alum means aluminum"],
      [/\bAL(?=[\s,.;]|$)/, "aluminum", "AL is a common abbreviation for aluminum"],
      [/\bcarbon\b/i, "carbon steel", "carbon steel, read with the mild steel gauge table"],
      [/\bmild\b/i, "carbon steel", "mild steel is carbon steel"],
      [/\b(?:CRS|HRS)\b/, "carbon steel", "CRS and HRS mean cold or hot rolled carbon steel"],
      [/\bcold[\s-]rolled\b/i, "carbon steel", "cold rolled sheet is carbon steel unless another metal is named"],
      [/\bhot[\s-]rolled\b/i, "carbon steel", "hot rolled is carbon steel unless another metal is named"],
      [/\bsteel\b/i, "carbon steel", "steel with no other metal named is read as carbon steel"]
    ].freeze

    # Grades that imply a material family when the family is not written.
    GRADE_MATERIAL = {
      "stainless steel" => /\b(?:304|316|321|430|201)L?\b/,
      "aluminum" => /\b(?:6061|5052|3003|7075|2024)\b/,
      "carbon steel" => /\b(?:A36|A572|A516|A1008|A366|A500|A513|A53)\b/
    }.freeze

    GRADES = [
      [%r{\b(304|316)\s*/\s*\1L\b}, ->(m) { "#{m[1]}/#{m[1]}L" }, nil, "dual certified grade: one heat that meets both"],
      [/\b(304|316|321|430|201)(L)?\b/, ->(m) { "#{m[1]}#{m[2]}" }, nil, "stainless steel grade"],
      [/\bA572\s*(?:Gr\.?|Grade)?\s*50\b/i, ->(_) { "A572 Gr 50" }, nil, "A572 Grade 50: 50 ksi minimum yield"],
      [/\bA516[-\s]*(?:Gr\.?|Grade)?\s*70\b/i, ->(_) { "A516-70" }, nil, "A516 Grade 70 pressure vessel plate"],
      [/\bA36\b/, ->(_) { "A36" }, nil, "A36: 36 ksi minimum yield"],
      [/\b(6061|5052|3003|7075|2024)(?:[-\s]?(T\d{1,3}|H\d{2,3}|O))?\b/, ->(m) { m[1] }, ->(m) { m[2] }, "aluminum alloy, temper is part of the grade"]
    ].freeze

    STANDARDS = [
      [/\bSA[-\s]?(240|312|516|479|276)\b/, ->(m) { "SA-#{m[1]}" }, "ASME SA: code material for Boiler and Pressure Vessel Code use"],
      [/\b(?:ASTM\s*)?A[-\s]?(240|276|479|312|500|513|53|516|572|1008|366|36|6)\b(?:\s*(?:Gr\.?|Grade)?\s*([A-C]|50|70)\b)?/i,
       ->(m) { grade = m[2]; "A#{m[1]}#{grade ? " Grade #{grade.upcase}" : ""}" }, "ASTM specification"],
      [/\b(?:ASTM\s*)?B[-\s]?(209|221)\b/i, ->(m) { "B#{m[1]}" }, "ASTM aluminum specification"],
      [/\bAMS[-\s]?\d{3,5}[A-Z]?\b/i, ->(m) { m[0].upcase }, "AMS aerospace specification (paid standard, not researched)"]
    ].freeze

    FORMS = [
      [/\bexpanded\b/i, "expanded metal"],
      [/\bingots?\b/i, "ingot"],
      [/\bsows?\b/i, "sow"],
      [/\b(?:shot|grit|beads?|abrasives?|garnet|oxide)\b/i, "abrasive"],
      [/\b(?:sq\.?|square)\s*tub(?:e|es|ing)\b/i, "square tube"],
      [/\brect(?:angle|angular)?\.?\s*tub(?:e|es|ing)\b/i, "rectangular tube"],
      [/\b(?:rd\.?|round)\s*tub(?:e|es|ing)\b/i, "round tube"],
      [/\btub(?:e|es|ing)\b/i, "tube"],
      [/\bpipe\b/i, "pipe"],
      [/\bsch(?:ed|edule)?\.?\s*\d+\b/i, "pipe"],
      [/\b(?:plates?|plt|PL)\b/, "plate"],
      [/\bsheets?\b|\bsht\b/i, "sheet"],
      [/\bflat\s*bars?\b|\bflats?\b|\bstrips?\b/i, "flat bar"],
      [/\b(?:rd\.?|round)\s*bars?\b|\brd\b/i, "round bar"],
      [/\bangles?\b|\bL\d/i, "angle"],
      [/\bchannels?\b/i, "channel"],
      [/\bbars?\b/i, "bar"]
    ].freeze

    FINISHES = [
      [/\b2B\b/, "2B", "2B is the standard cold rolled mill finish"],
      [/(?:\bNo\.?\s*4\b|#4)(?:\s*finish)?/i, "No. 4", "No. 4 is a brushed finish that varies between suppliers"],
      [/\bmill\s*finish\b/i, "mill finish", "mill finish as written"],
      [/#2\s*finish/i, "No. 2", "a vendor label that may mean 2B"]
    ].freeze

    PROCESSES = [
      [/\bcold[\s-]rolled\b|\bCRS\b|\bCR\b(?![A-Z])/i, "cold rolled"],
      [/\bhot[\s-]rolled\b|\bHRS\b|\bHR\b(?![A-Z])/i, "hot rolled"],
      [/\b(?:smls|seamless)\b/i, "seamless"],
      [/\bwelded\b/i, "welded"]
    ].freeze

    COATINGS = [
      [/\bgalv(?:anized|anised|\.)?\b/i, "galvanized"],
      [/\bG(?:60|90)\b/, "galvanized coating weight"],
      [/\bprimer\b/i, "primer"],
      [/\benamel\b/i, "enamel"]
    ].freeze

    GAUGE = /\b(\d{1,2})\s*(?:ga\.?|gauge|GA\.?)(?![a-z])/i
    SCHEDULE = /\bsch(?:ed|edule)?\.?\s*(\d+)\b/i
    YIELD = /\b(?:min(?:imum)?\.?\s*)?yield\s*(\d+)\s*ksi\b/i

    # Quantity as buyers write it. Trailing "x N" is handled by the parser.
    # A quantity number is never part of a fraction, a decimal, or a grade ("1/2 plate", "A516-70 plate").
    QUANTITIES = [
      [/\bqty\.?\s*:?\s*(\d+)\b/i, nil],
      [/(?<![\d\/.\-])\b(\d[\d,]*)\s*(?:lbs?\.?|pounds?)\b/i, "lb"],
      [/(?<![\d\/.\-])\b(\d[\d,]*)\s*(?:bags?|sacks?)\b/i, "bag"],
      [/(?<![\d\/.\-])\b(\d[\d,]*)\s*(?:drums?|pails?|skids?|pallets?|tons?|kgs?|kilos?)\b/i, :unit_as_written],
      [/(?<![\d\/.\-])\b(\d+)\s*(ea|each|pcs?|pieces?)\b/i, "each"],
      [/(?<![\d\/.\-])\b(\d+)\s*(sheets?|shts?)\b/i, "sheet"],
      [/(?<![\d\/.\-])\b(\d+)\s*(plates?|bars?|lengths?|sticks?|tubes?)\b/i, "each"],
      [/\bquantity\s*(?:of\s*)?(\d+)\b/i, nil]
    ].freeze

    QUANTITY_WORDS = {
      "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5, "six" => 6,
      "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10, "twelve" => 12, "twenty" => 20
    }.freeze
  end
end
