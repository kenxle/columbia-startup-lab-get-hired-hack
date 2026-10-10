# Builds data/metals/catalog.json: a constructed sample stock list of metals
# items for the RFQ matcher. Run: ruby tools/catalog_research/build_metals_catalog.rb
#
# Every item is sample data, not confirmed RudCo inventory, and carries no price.
# Gauge thicknesses come from the per-material tables in
# docs/research/20261010.01_rfq_sharper_angle/research_domain_rules.md, section 1.1.

require "json"

PROVENANCE = "constructed sample catalog, not confirmed RudCo inventory".freeze
GAUGE_SOURCE = "Metal Supermarkets sheet metal gauge chart (research_domain_rules.md 1.1)".freeze

GAUGE_TABLES = {
  "carbon steel" => { 10 => 0.1345, 11 => 0.1196, 12 => 0.1046, 14 => 0.0747, 16 => 0.0598, 18 => 0.0478, 20 => 0.0359 },
  "galvanized steel" => { 10 => 0.1382, 11 => 0.1233, 12 => 0.1084, 14 => 0.0785, 16 => 0.0635, 18 => 0.0516, 20 => 0.0396 },
  "stainless steel" => { 10 => 0.14062, 11 => 0.125, 12 => 0.10937, 14 => 0.07812, 16 => 0.0625, 18 => 0.050, 20 => 0.0375 },
  "aluminum" => { 10 => 0.1019, 11 => 0.09074, 12 => 0.08081, 14 => 0.06408, 16 => 0.05082, 18 => 0.04030, 20 => 0.03196 }
}.freeze

FRACTIONS = {
  0.125 => "1/8", 0.1875 => "3/16", 0.25 => "1/4", 0.375 => "3/8", 0.5 => "1/2", 0.75 => "3/4",
  1.0 => "1", 1.25 => "1-1/4", 1.5 => "1-1/2", 2.0 => "2", 3.0 => "3"
}.freeze

MATERIAL_CODES = { "stainless steel" => "SS", "carbon steel" => "CS", "galvanized steel" => "GV", "aluminum" => "AL" }.freeze

def frac(value) = FRACTIONS.fetch(value, format("%.3f", value).sub(/0+\z/, ""))

def thk_code(value) = format("%03d", (value * 1000).round)

def feet(inches) = (inches % 12).zero? ? "#{inches / 12} ft" : "#{inches} in"

def item(**fields)
  {
    catalog: "metals",
    catalog_provenance: PROVENANCE,
    finish: nil, temper: nil, gauge: nil, gauge_table: nil,
    thickness_in: nil, width_in: nil, length_in: nil,
    size_a_in: nil, size_b_in: nil, wall_in: nil, diameter_in: nil,
    nps: nil, schedule: nil, rfq_aliases: []
  }.merge(fields)
end

items = []

# Sheet in gauges, per material table.
sheet_lines = [
  { material: "stainless steel", grade: "304/304L", grades_satisfied: %w[304 304L 304/304L], finish: "2B",
    standard: "ASTM A240", code: "SS304", sizes: [ [ 48, 96 ], [ 48, 120 ], [ 60, 120 ] ] },
  { material: "stainless steel", grade: "304/304L", grades_satisfied: %w[304 304L 304/304L], finish: "#4",
    standard: "ASTM A240", code: "SS304", sizes: [ [ 48, 96 ], [ 48, 120 ] ] },
  { material: "stainless steel", grade: "316/316L", grades_satisfied: %w[316 316L 316/316L], finish: "2B",
    standard: "ASTM A240", code: "SS316", sizes: [ [ 48, 96 ], [ 48, 120 ] ] },
  { material: "carbon steel", grade: "CS Type B", grades_satisfied: [ "CS", "CS Type B", "CQ" ], finish: "cold rolled",
    standard: "ASTM A1008", code: "CR", sizes: [ [ 48, 96 ], [ 48, 120 ] ] },
  { material: "galvanized steel", grade: "G90", grades_satisfied: %w[G90], finish: "G90 coating",
    standard: "ASTM A653", code: "GV", sizes: [ [ 48, 96 ], [ 48, 120 ] ] },
  { material: "aluminum", grade: "5052", grades_satisfied: %w[5052], temper: "H32", finish: "mill",
    standard: "ASTM B209", code: "AL5052", sizes: [ [ 48, 96 ], [ 48, 120 ] ] }
]

sheet_lines.each do |line|
  GAUGE_TABLES.fetch(line[:material]).each do |gauge, thickness|
    line[:sizes].each do |width, length|
      finish_code = line[:finish].to_s.upcase.gsub(/[^A-Z0-9]/, "")
      finish_code = nil if %w[MILL COLDROLLED G90COATING].include?(finish_code)
      pn = [ "RC", line[:code], "SHT", "#{gauge}GA", "#{width}X#{length}", finish_code ].compact.join("-")
      temper = line[:temper] ? "-#{line[:temper]}" : ""
      items << item(
        pn: pn, form: "sheet", material: line[:material], grade: line[:grade], grades_satisfied: line[:grades_satisfied],
        temper: line[:temper], finish: line[:finish], standard: line[:standard],
        gauge: gauge, gauge_table: "#{line[:material]} sheet, #{GAUGE_SOURCE}", thickness_in: thickness,
        width_in: width, length_in: length, unit: "sheet",
        description: "#{line[:grade]}#{temper} #{line[:material]} sheet, #{gauge} ga (#{thickness} in), " \
                     "#{width} x #{length} in, #{line[:finish]}, #{line[:standard]}"
      )
    end
  end
end

# Plate in fractional thicknesses.
plate_lines = [
  { material: "stainless steel", grade: "304/304L", grades_satisfied: %w[304 304L 304/304L], finish: "HRAP #1",
    standard: "ASTM A240", code: "SS304", thicknesses: [ 0.1875, 0.25, 0.375, 0.5 ], sizes: [ [ 48, 96 ], [ 60, 120 ] ] },
  { material: "stainless steel", grade: "316/316L", grades_satisfied: %w[316 316L 316/316L], finish: "HRAP #1",
    standard: "ASTM A240 / ASME SA-240", code: "SS316", thicknesses: [ 0.375, 0.5 ], sizes: [ [ 60, 120 ] ] },
  { material: "carbon steel", grade: "A36/A572-50", grades_satisfied: %w[A36 A572-50 A36/A572-50], finish: "hot rolled",
    standard: "ASTM A36 / A572 Gr 50 dual certified", code: "A36",
    thicknesses: [ 0.1875, 0.25, 0.375, 0.5, 0.75, 1.0 ], sizes: [ [ 48, 96 ], [ 60, 120 ], [ 96, 240 ] ] },
  { material: "carbon steel", grade: "A516-70", grades_satisfied: %w[A516-70], finish: "hot rolled",
    standard: "ASTM A516 Gr 70", code: "A516", thicknesses: [ 0.5 ], sizes: [ [ 72, 120 ] ] },
  { material: "aluminum", grade: "6061", grades_satisfied: %w[6061], temper: "T651", finish: "mill",
    standard: "ASTM B209", code: "AL6061", thicknesses: [ 0.25, 0.5, 1.0 ], sizes: [ [ 48, 96 ] ] },
  { material: "aluminum", grade: "6061", grades_satisfied: %w[6061], temper: "T651", finish: "mill",
    standard: "ASTM B209", code: "AL6061", thicknesses: [ 2.0 ], sizes: [ [ 12, 24 ] ] }
]

plate_lines.each do |line|
  line[:thicknesses].each do |thickness|
    line[:sizes].each do |width, length|
      temper = line[:temper] ? "-#{line[:temper]}" : ""
      items << item(
        pn: "RC-#{line[:code]}-PLT-#{thk_code(thickness)}-#{width}X#{length}", form: "plate",
        material: line[:material], grade: line[:grade], grades_satisfied: line[:grades_satisfied],
        temper: line[:temper], finish: line[:finish], standard: line[:standard],
        thickness_in: thickness, width_in: width, length_in: length, unit: "plate",
        description: "#{line[:grade]}#{temper} #{line[:material]} plate, #{frac(thickness)} in, " \
                     "#{width} x #{length} in, #{line[:finish]}, #{line[:standard]}"
      )
    end
  end
end

# Square tube.
[
  [ "carbon steel", "A500 Gr B/C", %w[A500 A500-B A500-C], "ASTM A500 Gr B/C dual", "A500", 1.5, 0.120, 288 ],
  [ "carbon steel", "A500 Gr B/C", %w[A500 A500-B A500-C], "ASTM A500 Gr B/C dual", "A500", 2.0, 0.120, 288 ],
  [ "carbon steel", "A500 Gr B/C", %w[A500 A500-B A500-C], "ASTM A500 Gr B/C dual", "A500", 2.0, 0.188, 288 ],
  [ "carbon steel", "A500 Gr B/C", %w[A500 A500-B A500-C], "ASTM A500 Gr B/C dual", "A500", 3.0, 0.188, 288 ],
  [ "carbon steel", "A513", %w[A513], "ASTM A513 Type 5 (mechanical)", "A513", 2.0, 0.120, 288 ],
  [ "stainless steel", "304", %w[304 304L 304/304L], "ASTM A554 welded", "SS304", 1.25, 0.120, 240 ],
  [ "stainless steel", "304", %w[304 304L 304/304L], "ASTM A554 welded", "SS304", 1.5, 0.065, 240 ]
].each do |material, grade, satisfied, standard, code, size, wall, length|
  items << item(
    pn: "RC-#{code}-SQT-#{thk_code(size)}-#{thk_code(wall)}-#{length / 12}FT", form: "square tube",
    material: material, grade: grade, grades_satisfied: satisfied, standard: standard,
    size_a_in: size, size_b_in: size, wall_in: wall, thickness_in: wall, length_in: length, unit: "length",
    finish: material == "stainless steel" ? "mill" : "black",
    description: "#{grade} #{material} square tube, #{frac(size)} x #{frac(size)} in, #{wall} in wall, #{feet(length)}, #{standard}"
  )
end

# Angle and flat bar.
[
  [ "angle", 3.0, 3.0, 0.25, 240, "black", "A36" ],
  [ "angle", 2.0, 2.0, 0.25, 240, "black", "A36" ],
  [ "angle", 3.0, 3.0, 0.25, 240, "hot-dip galvanized", "A36G" ],
  [ "flat bar", 3.0, nil, 0.125, 240, "hot rolled", "A36" ],
  [ "flat bar", 2.0, nil, 0.25, 240, "hot rolled", "A36" ]
].each do |form, a, b, thickness, length, finish, code|
  size = b ? "#{frac(a)} x #{frac(b)} x #{frac(thickness)} in" : "#{frac(thickness)} x #{frac(a)} in"
  form_code = form == "angle" ? "ANG" : "FLT"
  items << item(
    pn: "RC-#{code}-#{form_code}-#{thk_code(a)}#{b ? "X#{thk_code(b)}" : ''}-#{thk_code(thickness)}-#{length / 12}FT",
    form: form, material: "carbon steel", grade: "A36", grades_satisfied: %w[A36], standard: "ASTM A36",
    size_a_in: a, size_b_in: b, width_in: (form == "flat bar" ? a : nil), thickness_in: thickness,
    length_in: length, finish: finish, unit: "length",
    description: "A36 carbon steel #{form}, #{size}, #{feet(length)}, #{finish}"
  )
end

items << item(
  pn: "RC-AL6061-FLT-1000-125-12FT", form: "flat bar", material: "aluminum", grade: "6061", grades_satisfied: %w[6061],
  temper: "T6", standard: "ASTM B221 (extruded)", width_in: 1.0, size_a_in: 1.0, thickness_in: 0.125, length_in: 144,
  finish: "mill", unit: "length", description: "6061-T6 aluminum flat bar, 1/8 x 1 in, 12 ft, extruded, ASTM B221"
)

# Round bar.
[ [ "304", %w[304 304L 304/304L], 2.0 ], [ "304", %w[304 304L 304/304L], 1.0 ], [ "316", %w[316 316L 316/316L], 1.0 ] ].each do |grade, satisfied, dia|
  items << item(
    pn: "RC-SS#{grade}-RND-#{thk_code(dia)}-12FT", form: "round bar", material: "stainless steel", grade: grade,
    grades_satisfied: satisfied, standard: "ASTM A276", diameter_in: dia, length_in: 144, finish: "cold finished",
    unit: "length", description: "#{grade} stainless steel round bar, #{frac(dia)} in diameter, 12 ft, cold finished, ASTM A276"
  )
end

# Pipe.
[ [ 2.0, "seamless", "SMLS" ], [ 1.0, "seamless", "SMLS" ], [ 2.0, "welded", "WLD" ] ].each do |nps, process, code|
  items << item(
    pn: "RC-SS304-PIPE-#{thk_code(nps)}-S40-#{code}-20FT", form: "pipe", material: "stainless steel", grade: "304/304L",
    grades_satisfied: %w[304 304L 304/304L], standard: "ASTM A312", nps: nps, schedule: "40", process: process,
    length_in: 240, finish: "pickled", unit: "length",
    description: "304/304L stainless steel pipe, #{frac(nps)} in NPS, schedule 40, #{process}, 20 ft, ASTM A312"
  )
end

items.each { |entry| entry[:rfq_aliases] = [ entry[:pn], entry[:pn].downcase ] }
duplicate = items.group_by { |entry| entry[:pn] }.find { |_, group| group.size > 1 }
abort "Duplicate PN: #{duplicate.first}" if duplicate

output = File.expand_path("../../data/metals/catalog.json", __dir__)
Dir.mkdir(File.dirname(output)) unless Dir.exist?(File.dirname(output))
File.write(output, JSON.pretty_generate(items) + "\n")
puts "Wrote #{items.size} items to #{output}"
