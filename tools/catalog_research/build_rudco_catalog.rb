# Builds data/rudco/catalog.json from RudCo's public website bundle: the
# abrasives (steel shot, grit, aluminum oxide, ...) and aluminum ingot alloys
# RudCo lists, with the sizes, specs, packaging and list prices shown there.
#
#   curl -sL https://www.rud-co.com/assets/index-B04wKX3n.js -o /tmp/rudco.js
#   ruby tools/catalog_research/build_rudco_catalog.rb /tmp/rudco.js
#
# The bundle is read as text with regular expressions; it is never executed.
# Products come from RudCo's site, but stock and prices are not confirmed by
# RudCo: list prices are labeled as website list prices, not quote prices.

require "json"
require "digest"
require "time"

SOURCE_URL = "https://www.rud-co.com/assets/index-B04wKX3n.js".freeze
PROVENANCE = "RudCo website product listing; stock and price not confirmed by RudCo".freeze

path = ARGV.fetch(0) { abort "Usage: ruby #{__FILE__} path/to/rudco-site.js" }
source = File.read(path, encoding: "UTF-8")

def strings(block, key)
  block.scan(/#{key}:\[((?:"[^"]*",?)*)\]/).flatten.first.to_s.scan(/"([^"]*)"/).flatten
end

def spec(block, label)
  block[/\{label:"#{Regexp.escape(label)}",value:"([^"]*)"\}/, 1]
end

def code(text) = text.upcase.gsub(/[^A-Z0-9]+/, "")

ABRASIVE_MATERIALS = {
  "steel-shot" => "steel shot", "steel-grit" => "steel grit", "stainless-steel-shot" => "stainless steel shot",
  "aluminum-oxide" => "aluminum oxide", "garnet" => "garnet", "glass-beads" => "glass bead",
  "corn-cob" => "corn cob"
}.freeze

items = []

# Abrasive product records: {id:"steel-shot",name:"Steel Shot",...,variants:[{name,size,price}],packaging:[...]}
source.scan(/\{id:"([a-z0-9-]+)",name:"([^"]+)",slug:"[^"]+",tagline:"([^"]*)".*?variants:\[(.*?)\],applications:.*?packaging:\[(.*?)\]/m) do |id, name, tagline, variants, packaging|
  block = Regexp.last_match(0)
  material = ABRASIVE_MATERIALS.fetch(id, name.downcase)
  packs = packaging.scan(/"([^"]*)"/).flatten
  standard = spec(block, "Standard")
  variants.scan(/\{name:"([^"]+)",size:(?:"([^"]*)"|'([^']*)'),price:"([^"]*)"\}/) do |variant, size_double, size_single, price|
    size = size_double || size_single
    list_price = price[/\$([\d.]+)\/lb/, 1]&.to_f
    items << {
      pn: "RC-#{code(id)}-#{code(variant)}",
      catalog: "rudco",
      catalog_provenance: PROVENANCE,
      form: "abrasive",
      material: material,
      grade: variant,
      grades_satisfied: [ variant, variant.sub(/\s*\(.*\)/, "") ].uniq,
      size: size,
      standard: standard,
      finish: nil,
      unit: "lb",
      packaging: packs,
      description: "#{name} #{variant} (#{size})#{standard ? ", #{standard}" : ''}. #{tagline}",
      list_price_usd_per_lb: list_price,
      list_price_source: list_price && { url: "https://www.rud-co.com/abrasives/#{id}", kind: "RudCo website list price", text: price },
      rfq_aliases: [ variant, variant.delete("-"), "#{material} #{variant}" ]
    }
  end
end

# Aluminum alloy records: Rj=[{slug:"p1020",name:"P1020",displayName:...,forms:[...],specifications:[...],packaging:[...]}]
alloy_list = source[/Rj=\[(\{slug:"p1020".*?)\]\s*[,;]\s*[A-Za-z_$]{1,4}=/m, 1].to_s
alloy_list.scan(/\{slug:"([a-z0-9-]+)",name:"([^"]+)",displayName:"([^"]+)",category:"([^"]+)",tagline:"([^"]*)"(.*?)related:/m) do |slug, name, display, category, tagline, rest|
  forms = strings(rest, "forms")
  specs = strings(rest, "specifications")
  packs = strings(rest, "packaging")
  forms.each do |form_text|
    form = form_text.match?(/sow/i) ? "sow" : "ingot"
    weight = form_text[/\(([^)]*)\)/, 1]
    form_code = code(form_text.sub(/\(.*\)/, ""))
    items << {
      pn: "RC-AL-#{code(name)}-#{form_code}",
      catalog: "rudco",
      catalog_provenance: PROVENANCE,
      form: form,
      form_detail: form_text,
      material: "aluminum",
      grade: name,
      grades_satisfied: [ name, name.sub(/\.\d\z/, "") ].uniq,
      category: category,
      standard: specs.join(" / "),
      unit: "lb",
      piece_weight: weight,
      packaging: packs,
      description: "#{display}, #{form_text}. #{tagline} Specs: #{specs.join(', ')}.",
      list_price_usd_per_lb: nil,
      list_price_source: nil,
      rfq_aliases: [ name, "#{name} #{form}", "#{name} aluminum #{form}" ],
      source_slug: slug
    }
  end
end

abort "No products found; the site bundle layout may have changed." if items.empty?
duplicate = items.group_by { |entry| entry[:pn] }.find { |_, group| group.size > 1 }
abort "Duplicate PN: #{duplicate.first}" if duplicate

output_dir = File.expand_path("../../data/rudco", __dir__)
Dir.mkdir(output_dir) unless Dir.exist?(output_dir)
File.write(File.join(output_dir, "catalog.json"), JSON.pretty_generate(items) + "\n")
File.write(File.join(output_dir, "source_manifest.json"), JSON.pretty_generate(
  source_url: SOURCE_URL,
  fetched_at: File.mtime(path).utc.iso8601,
  sha256: Digest::SHA256.file(path).hexdigest,
  item_count: items.size,
  note: "Products, sizes, specs and list prices as shown on RudCo's public website. Not confirmed stock or quote prices."
) + "\n")
puts "Wrote #{items.size} items to #{output_dir}/catalog.json"
items.group_by { |entry| entry[:material] }.each { |material, group| puts "  #{material}: #{group.map { |entry| entry[:grade] }.uniq.join(', ')}" }
