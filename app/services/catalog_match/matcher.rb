module CatalogMatch
  # Suggests the catalog item(s) a buyer's description means.
  #
  # Each item is checked field by field against the reading. A field that agrees
  # is exact; a field that is close (a 4% thickness gap, a different spec than
  # the one in the catalog) is near and becomes a question; a field that disagrees
  # rules the item out. The best items without conflicts are the suggestions.
  #
  # Outcomes follow the workflow: "match" (one item fits), "candidates" (two or
  # more fit, or one fits with something to confirm), "no_match" (nothing fits;
  # the closest items are listed but never forced onto the line).
  class Matcher
    Result = Struct.new(:outcome, :reading, :candidates, :closest, :question, keyword_init: true) do
      def match? = outcome == "match"
      def best = candidates.first
    end

    Candidate = Struct.new(:item, :checks, keyword_init: true) do
      def exact = checks.select { |check| check[:status] == :exact }
      def near = checks.select { |check| check[:status] == :near }
      def conflicts = checks.select { |check| check[:status] == :conflict }
      def score = exact.size * 2 + near.size
      def rank_key = [ conflicts.size, near.size, -exact.size ]

      # 0 to 100: how much of what the buyer wrote this item agrees with.
      def confidence
        return 0 if checks.empty? || conflicts.any?

        ((exact.size + near.size * 0.5) / checks.size * 100).round
      end
    end

    # Steel tube wall gauges (research_domain_rules.md 1.1, tube wall column).
    TUBE_GAUGE = { 10 => 0.134, 11 => 0.120, 12 => 0.109, 14 => 0.083, 16 => 0.065, 18 => 0.049, 20 => 0.035 }.freeze
    THICKNESS_EXACT = 0.015
    THICKNESS_NEAR = 0.05
    MAX_CANDIDATES = 6
    QUESTION_FIELDS = {
      "material" => "material", "grade" => "grade", "form" => "form", "temper" => "temper", "finish" => "finish",
      "thickness_in" => "thickness", "size" => "size", "length_in" => "length", "process" => "process",
      "standard" => "spec", "pn" => "part number"
    }.freeze

    # Fields the rules must settle before a line can match without the LLM.
    LLM_TRIGGER_FIELDS = %w[material form].freeze

    def self.call(description, client: nil, catalog: Catalog.default, given: {}, llm: LlmReader.default, confirmed_terms: [])
      terms = client && Array(confirmed_terms).empty? ? ClientMemory.new(client).terms : []
      given = (given || {}).to_h.stringify_keys
      reading = DescriptionReader.read(description, client_terms: terms, given: given, confirmed_terms: confirmed_terms)
      if llm && reading.part_numbers.empty? && needs_llm?(reading)
        llm_given = llm.read(description) || {}
        # The LLM fills only what the rules and processing left open.
        extra = llm_given.reject { |name, _| given.key?(name) || reading.set?(name) }
        reading = DescriptionReader.read(description, client_terms: terms, given: given.merge(extra), confirmed_terms: confirmed_terms) if extra.any?
      end
      new(reading, catalog).call
    end

    def self.needs_llm?(reading)
      LLM_TRIGGER_FIELDS.any? { |field| !reading.set?(field) } || reading.unknown_words.size >= 2
    end

    def initialize(reading, catalog)
      @reading = reading
      @catalog = catalog
    end

    def call
      return part_number_result if @reading.part_numbers.any? && part_number_result
      return empty_result if @reading.product_fields.empty?

      ranked = @catalog.items.map { |item| Candidate.new(item: item, checks: checks_for(item)) }
                       .reject { |candidate| candidate.checks.empty? }
                       .sort_by { |candidate| [ candidate.rank_key, candidate.item["pn"] ] }
      fitting = ranked.select { |candidate| candidate.conflicts.empty? }
      return no_match_result(ranked) if fitting.empty?

      best_key = fitting.first.rank_key
      top = fitting.select { |candidate| candidate.rank_key == best_key }.first(MAX_CANDIDATES)
      build_result(top)
    end

    private

    def build_result(top)
      if top.size == 1 && top.first.near.empty? && @reading.questions.empty?
        return Result.new(outcome: "match", reading: @reading, candidates: top, closest: [], question: nil)
      end

      question = @reading.questions.first ||
                 near_question(top.first) ||
                 choice_question(top)
      Result.new(outcome: "candidates", reading: @reading, candidates: top, closest: [], question: question)
    end

    def part_number_result
      @part_number_result ||= begin
        exact = @reading.part_numbers.filter_map { |pn| @catalog.find(pn) }
        if exact.any?
          # The part number names the item, but every other attribute the
          # buyer wrote is still checked against it; a disagreement is asked.
          candidates = exact.map { |item| Candidate.new(item: item, checks: [ pn_check(item, :exact) ] + checks_for(item)) }
          disagreement = candidates.flat_map { |candidate| candidate.conflicts + candidate.near }.first
          question = if candidates.size > 1
                       "The line names #{candidates.size} part numbers. Do you need all of them?"
                     elsif disagreement
                       disagreement[:question] ||
                         "The line names #{candidates.first.item['pn']}, but also says \"#{disagreement[:buyer_text]}\" " \
                         "(#{disagreement[:field]}); the catalog item is #{disagreement[:catalog_value].presence || 'different'}. Which is right?"
                     end
          outcome = question ? "candidates" : "match"
          Result.new(outcome: outcome, reading: @reading, candidates: candidates, closest: [], question: question)
        else
          related_part_numbers
        end
      end
    end

    # AN3-13 and AN3-13A differ only by the drilled shank; offer the variant in the catalog.
    def related_part_numbers
      requested = @reading.part_numbers.first
      base = requested.sub(/A\z/, "")
      related = @catalog.items.select { |item| item["pn"].to_s.upcase.match?(/\A#{Regexp.escape(base)}A?\z/) }
      return nil if related.empty?

      candidates = related.map { |item| Candidate.new(item: item, checks: [ pn_check(item, :near) ]) }
      Result.new(outcome: "candidates", reading: @reading, candidates: candidates, closest: [],
                 question: "#{requested} is not in our catalog. The catalog has #{related.map { |item| item['pn'] }.join(' and ')}, " \
                           "which differs in the drilled shank. Will that work?")
    end

    def pn_check(item, status)
      requested = @reading.part_numbers.first
      if (term = @reading.remembered_term)
        return { field: "pn", status: status, buyer_text: @reading.text, catalog_value: item["pn"], source: "client_memory",
                 explanation: "#{term.explanation_prefix} this exact request was approved as #{item['pn']}" }
      end

      { field: "pn", status: status, buyer_text: requested, catalog_value: item["pn"], source: "text",
        explanation: status == :exact ? "part number #{item['pn']} is in the catalog" : "closest catalog part number to #{requested}" }
    end

    def empty_result
      Result.new(outcome: "no_match", reading: @reading, candidates: [], closest: [],
                 question: "We could not read a product from this line. What material, form and size do you need?")
    end

    def no_match_result(ranked)
      closest = ranked.sort_by { |candidate| [ candidate.conflicts.size, -candidate.exact.size ] }.first(3)
      Result.new(outcome: "no_match", reading: @reading, candidates: [], closest: closest,
                 question: "Our catalog has no item that matches this line. #{closest_hint(closest)}".strip)
    end

    def closest_hint(closest)
      return "" if closest.empty?

      conflict = closest.first.conflicts.first
      "The closest item, #{closest.first.item['pn']}, differs on #{conflict[:field].tr('_', ' ')}: #{conflict[:explanation]}."
    end

    def near_question(candidate)
      near = candidate.near.first
      near && near[:question]
    end

    # Ask about the first field that differs between the fitting items.
    def choice_question(top)
      QUESTION_FIELDS.each do |field, label|
        values = top.map { |candidate| display_value(candidate.item, field) }.uniq
        next if values.size < 2 || values.any?(&:nil?)

        return "Which #{label} do you need: #{values.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}?"
      end
      "Several catalog items fit. Which one do you need: #{top.map { |candidate| candidate.item['pn'] }.join(', ')}?"
    end

    def display_value(item, field)
      case field
      when "size"
        dims = [ item["width_in"], item["length_in"] ].compact
        dims.size == 2 && %w[sheet plate].include?(item["form"]) ? dims.map { |value| inches(value) }.join(" x ") + " in" : nil
      when "thickness_in" then item["thickness_in"] && "#{item['thickness_in']} in"
      when "length_in" then item["length_in"] && "#{inches(item['length_in'] / 12.0)} ft"
      else item[field]
      end
    end

    # ---- field checks ----------------------------------------------------

    def checks_for(item)
      fields = @reading.product_fields
      return bolt_checks(item, fields) if item["form"] == "bolt" || fields.dig("form", "value") == "bolt"

      fields.filter_map { |name, field| metal_check(item, name, field) }
    end

    def metal_check(item, name, field)
      value = field["value"]
      case name
      when "material" then material_check(item, field)
      when "grade" then grade_check(item, field)
      when "temper" then temper_check(item, field)
      # "screw" fits "machine screw"; "nut" fits "plain hex nut".
      when "form" then equal_check(field, "form", item["form"], value == item["form"] || item["form"].to_s.end_with?(" #{value}"))
      when "thread" then equal_check(field, "thread", item["thread"], value == item["thread"])
      when "gauge" then gauge_check(item, field)
      when "thickness" then thickness_check(item, field)
      when "width" then plan_dimension_check(item, field, "width")
      when "length" then length_check(item, field)
      when "size_a", "size_b" then equal_check(field, "size", item[name + "_in"], close?(value, item[name + "_in"]))
      when "diameter" then equal_check(field, "diameter", item["diameter_in"], close?(value, item["diameter_in"]))
      when "nps" then equal_check(field, "pipe size", item["nps"], close?(value, item["nps"]))
      when "schedule" then equal_check(field, "schedule", item["schedule"], value.to_s == item["schedule"].to_s)
      when "process" then equal_check(field, "process", item["process"], value == item["process"])
      when "finish" then finish_check(item, field)
      when "standard" then standard_check(item, field)
      end
    end

    def bolt_checks(item, fields)
      return [ conflict(fields.values.first, "form", item["form"], "this item is not a bolt") ] unless item["form"] == "bolt"

      fields.filter_map do |name, field|
        value = field["value"]
        case name
        when "form" then exact(field, "form", "bolt")
        when "diameter" then equal_check(field, "diameter", item["diameter_in"], close?(value, item["diameter_in"]))
        when "thread" then equal_check(field, "thread", item["thread"], value == item["thread"])
        when "grip" then equal_check(field, "grip", item["grip_length_in"], close?(value, item["grip_length_in"]))
        when "drilled" then equal_check(field, "drilled shank", item["shank_drilled"] ? "drilled" : "undrilled", value == item["shank_drilled"])
        when "finish" then equal_check(field, "finish", item["finish"], item["finish"].to_s.include?(value.to_s))
        when "material", "grade" then nil
        else conflict(field, name, nil, "a bolt has no #{name.tr('_', ' ')}")
        end
      end
    end

    def material_check(item, field)
      wanted = field["value"]
      galvanized_stock = wanted == "galvanized steel" && item["material"] == "carbon steel" && item["finish"].to_s.include?("galvanized")
      equal_check(field, "material", item["material"], wanted == item["material"] || galvanized_stock)
    end

    def grade_check(item, field)
      wanted = normalize_grade(field["value"])
      satisfied = Array(item["grades_satisfied"]).map { |grade| normalize_grade(grade) }
      return conflict(field, "grade", item["grade"], "this item is #{item['grade'] || 'not graded'}") unless satisfied.include?(wanted)

      dual = item["grade"].to_s.include?("/") && !normalize_grade(item["grade"]).eql?(wanted)
      exact(field, "grade", item["grade"], dual ? "#{item['grade']} is dual certified, so it meets #{field['value']}" : nil)
    end

    def temper_check(item, field)
      wanted = field["value"]
      return exact(field, "temper", item["temper"]) if wanted == item["temper"]
      return conflict(field, "temper", item["temper"], "this item has no temper") if item["temper"].nil?

      if wanted == "T6" && item["temper"] == "T651" && item["form"] == "plate"
        return near(field, "temper", item["temper"], "6061-T6 plate is usually supplied as T651, the stress-relieved form",
                    "You wrote 6061-T6 plate. Plate is usually T651 (stress relieved). Is T651 acceptable?")
      end
      conflict(field, "temper", item["temper"], "this item is #{item['temper']}")
    end

    def gauge_check(item, field)
      gauge = field["value"]
      if item["form"] == "square tube"
        wall = TUBE_GAUGE[gauge]
        return conflict(field, "gauge", item["wall_in"], "no tube wall table entry for #{gauge} ga") unless wall

        return equal_check(field, "thickness", item["wall_in"], close?(wall, item["wall_in"]),
                           "#{gauge} ga tube wall is #{wall} in (steel tube wall table)")
      end
      return conflict(field, "gauge", item["thickness_in"], "this item is sold by thickness, not gauge") if item["gauge"].nil?

      equal_check(field, "gauge", "#{item['gauge']} ga (#{item['thickness_in']} in)", gauge == item["gauge"],
                  "#{gauge} ga #{item['material']} is #{item['thickness_in']} in (#{item['material']} gauge table)")
    end

    def thickness_check(item, field)
      wanted = field["value"].to_f
      actual = (item["wall_in"] || item["thickness_in"]).to_f
      return conflict(field, "thickness", nil, "this item has no thickness") if actual.zero?

      gap = (actual - wanted) / wanted
      label = item["gauge"] ? "#{item['gauge']} ga (#{actual} in)" : "#{actual} in"
      if gap.abs <= THICKNESS_EXACT || (actual - wanted).abs <= 0.0015
        exact(field, "thickness", label)
      elsif gap.abs <= THICKNESS_NEAR
        percent = (gap * 100).round(1)
        near(field, "thickness", label, "#{label} is #{percent.abs}% #{percent.positive? ? 'thicker' : 'thinner'} than the #{wanted} in written",
             "You wrote \"#{field['text']}\". The nearest catalog item is #{label}. Do you need exactly that thickness, or is #{label} acceptable?")
      else
        conflict(field, "thickness", label, "this item is #{label}")
      end
    end

    # Sheet and plate sizes can be written either way round (48 x 96 or 96 x 48).
    def plan_dimension_check(item, field, _name)
      dims = [ item["width_in"], item["length_in"] ].compact
      wanted = field["value"].to_f
      equal_check(field, "size", dims.map { |value| inches(value) }.join(" x "), dims.any? { |value| close?(wanted, value) })
    end

    def length_check(item, field)
      wanted = field["value"].to_f
      return plan_dimension_check(item, field, "length") if %w[sheet plate].include?(item["form"])
      return conflict(field, "length", nil, "this item has no catalog length") if item["length_in"].nil?
      return exact(field, "length", "#{inches(item['length_in'] / 12.0)} ft") if close?(wanted, item["length_in"])

      if wanted < item["length_in"]
        return near(field, "length", "#{inches(item['length_in'] / 12.0)} ft",
                    "the catalog item comes in #{inches(item['length_in'] / 12.0)} ft lengths; #{inches(wanted / 12.0)} ft needs a cut",
                    "The catalog item comes in #{inches(item['length_in'] / 12.0)} ft lengths. Should it be cut to #{inches(wanted / 12.0)} ft?")
      end
      conflict(field, "length", "#{inches(item['length_in'] / 12.0)} ft", "the catalog length is shorter than #{inches(wanted / 12.0)} ft")
    end

    def finish_check(item, field)
      equal_check(field, "finish", item["finish"], item["finish"].to_s.casecmp?(field["value"].to_s))
    end

    def standard_check(item, field)
      stocked = item["standard"].to_s.upcase.gsub(/[^A-Z0-9]/, "")
      wanted = [ field["value"], field["also"] ].compact
      matching = wanted.find { |spec| stocked.match?(/(?<![A-Z0-9])#{spec}|ASTM#{spec}|ASME#{spec}|\A#{spec}/) || stocked.include?(spec) }
      return exact(field, "spec", item["standard"]) if matching

      near(field, "spec", item["standard"], "the catalog lists this item to #{item['standard']}, not #{wanted.join(' or ')}",
           "You wrote #{wanted.join(' / ')}. Our catalog lists this item to #{item['standard']}. Is that acceptable?")
    end

    def normalize_grade(grade)
      grade.to_s.upcase.gsub(/[\s-]+/, "").sub(/GR\.?/, "")
    end

    def equal_check(field, label, catalog_value, equal, explanation = nil)
      equal ? exact(field, label, catalog_value, explanation) : conflict(field, label, catalog_value, "this item is #{catalog_value.presence || 'not specified'}")
    end

    def exact(field, label, catalog_value, explanation = nil)
      check(field, label, catalog_value, :exact, explanation || field["explanation"])
    end

    def near(field, label, catalog_value, explanation, question)
      check(field, label, catalog_value, :near, explanation).merge(question: question)
    end

    def conflict(field, label, catalog_value, explanation)
      check(field, label, catalog_value, :conflict, explanation)
    end

    def check(field, label, catalog_value, status, explanation)
      { field: label, status: status, buyer_text: field["text"], catalog_value: catalog_value,
        explanation: explanation, source: field["source"] }
    end

    def close?(wanted, actual)
      return false if wanted.nil? || actual.nil?

      (wanted.to_f - actual.to_f).abs <= [ actual.to_f.abs * 0.005, 0.002 ].max
    end

    def inches(value)
      value.to_f == value.to_i ? value.to_i.to_s : value.to_f.round(3).to_s
    end
  end
end
