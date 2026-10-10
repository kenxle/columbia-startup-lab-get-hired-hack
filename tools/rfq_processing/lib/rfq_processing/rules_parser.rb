# frozen_string_literal: true

module RfqProcessing
  # Deterministic reading of one RFQ line. Every field carries the exact source
  # words, the rule used, and a confidence. Nothing is guessed: a value the
  # rules cannot settle becomes an unknown or a conflict, which the readiness
  # rule turns into a buyer question.
  #
  # The Claude parser (llm_parser.rb) produces the same Reading shape from
  # messier text; this parser is the offline baseline and the cross-check.
  class RulesParser
    Reading = Struct.new(:fields, :evidence, :confidence, :assumptions, :rules_used, :conflicts, :unknowns, :location,
                         keyword_init: true) do
      def [](key) = fields[key.to_s]
    end

    NUM = /\d+[\s-]\d+\/\d+|\d+\/\d+|\d*\.\d+|\d+/
    UNIT = /"|”|''|in\b\.?|inch(?:es)?\b|'|’|ft\b\.?|feet\b|foot\b|mm\b/
    SEP = /\s*(?:x|X|×|by)\s*/
    CHAIN = /(?:#{NUM})\s*(?:#{UNIT})?(?:#{SEP}(?:#{NUM})\s*(?:#{UNIT})?)+/
    ELEMENT = /(#{NUM})\s*(#{UNIT})?/
    SUFFIX = /\A\s*(long|lg|thick|thk|wall|wide|dia\.?|diameter|od|nominal)\b/i
    TRAILING_QTY = /(?<=\s)x\s*(\d{1,4})(?=\s*\z|\s+[A-Za-z(])(?!\s*(?:in|inch(?:es)?|ft|feet|foot|ga|gauge|mm|by|thick|thk|long|wide|wall)\b)/i
    STANDALONE = /(#{NUM})\s*(#{UNIT})?(?:\s*(long|lg|thick|thk|wall|wide|dia\.?|diameter|od)\b)?/
    PART_NUMBER = /\b(AN|MS|NAS)(\d{1,2})(?:-(\d{1,3})([AH]?)|H(\d{1,3})A?)?\b/

    GAUGE_TOLERANCE = 0.02 # a decimal within 2% of the table value is the same thickness, rounded
    NEAR_GAUGE = 0.06      # a decimal within 6% but outside tolerance is the gauge trap: ask
    SHEET_PLATE_LOW = 0.118 # 3 mm; between this and 0.25 in, sheet or plate is the buyer's word
    SHEET_PLATE_HIGH = 0.25

    def self.parse(text, position: 1, location: nil, buyer_terms: [])
      new(text, position: position, location: location, buyer_terms: buyer_terms).parse
    end

    def initialize(text, position:, location:, buyer_terms: [])
      @text = text.to_s
      @position = position
      @location = location || "line #{position}"
      @buyer_terms = Array(buyer_terms)
      @fields = {}
      @evidence = {}
      @confidence = {}
      @assumptions = []
      @rules = []
      @conflicts = []
      @unknowns = []
      @occupied = []
    end

    def parse
      read_buyer_terms
      read_part_number
      read_lexicon
      read_rudco_products
      read_gauge_and_schedule
      read_quantity
      read_dimensions
      resolve_material
      resolve_thickness
      check_conflicts
      note_unknowns
      Reading.new(fields: @fields, evidence: @evidence, confidence: @confidence, assumptions: @assumptions,
                  rules_used: @rules, conflicts: @conflicts, unknowns: @unknowns, location: @location)
    end

    private

    # ---- recording helpers -------------------------------------------------

    def set(field, value, match_or_text, explanation, confidence: 0.95, occupy: false)
      return if value.nil?

      text, range = match_or_text.is_a?(MatchData) ? [match_or_text[0], match_or_text.begin(0)...match_or_text.end(0)] : [match_or_text, nil]
      @fields[field] = value
      @evidence[field] = { "text" => text, "location" => range ? "#{@location}, chars #{range.begin + 1}-#{range.end}" : @location,
                           "explanation" => explanation }
      @confidence[field] = confidence
      @occupied << range if occupy && range
    end

    def occupy(match)
      @occupied << (match.begin(0)...match.end(0))
    end

    def occupied?(range)
      @occupied.any? { |o| o.begin < range.end && range.begin < o.end }
    end

    # Text with occupied spans blanked, so number scans skip grades, specs, gauges, and quantities.
    def masked
      chars = @text.dup
      @occupied.each { |r| chars[r] = " " * (r.end - r.begin) }
      chars
    end

    def conflict(code, message, fields = [])
      @conflicts << { "code" => code, "message" => message, "fields" => fields }
    end

    def unknown(field, reason)
      @unknowns << { "field" => field, "reason" => reason } unless @unknowns.any? { |u| u["field"] == field }
    end

    # ---- what this buyer's words mean (workflow step 9) --------------------

    def read_buyer_terms
      BuyerProfile.apply(@buyer_terms, @text).each do |hit|
        hit[:fields].each do |field, value|
          set(field, value, hit[:match], hit[:explanation], confidence: 0.9, occupy: true)
        end
        @rules << "Buyer profile: \"#{hit[:term]}\" means #{hit[:describe]} (#{hit[:how]})"
      end
    end

    # ---- RudCo's own products: abrasives and aluminum ingot ---------------

    def read_rudco_products
      material = @fields["material"]
      form = @fields["form"]
      if %w[steel\ shot steel\ grit].include?(material) || (form == "abrasive" && material.to_s.start_with?("steel"))
        if (m = /\b([SG])\s?-?\s?(\d{2,3})\b/.match(@text))
          set("grade", "#{m[1]}-#{m[2]}", m, "#{m[1] == 'S' ? 'shot' : 'grit'} size designation (SAE J444)", occupy: true)
        end
      elsif %w[ingot sow].include?(form) || /\bP1020\b|\bA356\b/.match?(@text)
        if (m = /\b(P1020|A356|356|6061|5052|3003)\b/.match(@text))
          set("grade", m[1], m, "aluminum alloy or purity designation for ingot", occupy: true)
          set("material", "aluminum", m, "#{m[1]} is an aluminum ingot designation", confidence: 0.9) unless @fields["material"]
        end
        @fields["form"] ||= "ingot"
      elsif form == "abrasive" && material.nil? && (m = /\b(aluminum oxide|garnet|glass bead)\b/i.match(@text))
        set("material", m[1].downcase, m, "abrasive media as written")
      end
    end

    # ---- hardware part numbers --------------------------------------------

    def read_part_number
      m = PART_NUMBER.match(@text)
      return unless m

      family = "#{m[1]}#{m[2]}"
      dash = m[3] || m[5]
      if dash
        set("part_number", m[0], m, "Standard #{m[1]} part number: family #{family}, dash #{dash}#{suffix_meaning(m)}", occupy: true)
      else
        set("part_family", family, m, "#{m[1]} family without a dash number, so no full part number", confidence: 0.9, occupy: true)
        unknown("part_number", "the dash number (length) is not written")
      end
      @fields["form"] = "hex-head bolt" if m[1] == "AN" && %w[3 4 5 6 7 8].include?(m[2])
      @rules << "Part number parser: #{m[0]}"
    end

    def suffix_meaning(m)
      return ", suffix A means undrilled shank" if m[4] == "A"
      return ", H means drilled head" if m[4] == "H" || m[5]

      ", plain dash number means drilled shank"
    end

    # ---- words ------------------------------------------------------------

    def read_lexicon
      Lexicon::FORMS.each do |pattern, form|
        m = pattern.match(@text)
        next unless m

        set("form", form, m, "#{m[0]} means #{form}")
        break
      end

      Lexicon::MATERIALS.each do |pattern, material, why|
        m = pattern.match(@text)
        next unless m
        next if material == "carbon steel" && why.start_with?("steel with") && @fields["material"]

        set("material", material, m, why)
        break
      end

      Lexicon::GRADES.each do |pattern, grade_fn, temper_fn, why|
        m = pattern.match(@text)
        next unless m

        set("grade", grade_fn.call(m), m, why, occupy: true)
        temper = temper_fn&.call(m)
        set("temper", temper, m, "temper is written with the alloy") if temper
        break
      end

      standards = []
      Lexicon::STANDARDS.each do |pattern, std_fn, why|
        @text.to_enum(:scan, pattern).each do
          m = Regexp.last_match
          next if @fields["grade"] && @evidence["grade"]["text"] == m[0] && !m[0].start_with?("A5", "SA")

          standards << [std_fn.call(m), m, why]
          occupy(m)
        end
      end
      standards.uniq! { |s| s[0] }
      either = standards.size == 2 && @text[standards[0][1].end(0)...standards[1][1].begin(0)].to_s.match?(/\A\s*(?:or|\/)\s*\z/i)
      if standards.size == 1
        set("standard", standards[0][0], standards[0][1], standards[0][2])
      elsif either
        names = standards.map(&:first)
        @fields["standard"] = names.join(" or ")
        @evidence["standard"] = { "text" => @text[standards[0][1].begin(0)...standards[1][1].end(0)], "location" => @location,
                                  "explanation" => "either specification is acceptable, as written; dual-certified stock meets both" }
        @confidence["standard"] = 0.9
        @fields["grade"] = names.join(" or ") if names.all? { |n| n.match?(/\AA(36|572)/) }
        @evidence["grade"] = @evidence["standard"] if @fields["grade"]&.include?(" or ")
        @assumptions << "The buyer accepts #{names.join(' or ')}; one plate certified to both fits."
      elsif standards.size > 1
        set("standard", nil, standards[0][1], "")
        @fields["standards"] = standards.map(&:first)
        @evidence["standard"] = { "text" => standards.map { |s| s[1][0] }.join(" and "), "location" => @location,
                                  "explanation" => "two specifications are written on one line: #{standards.map(&:first).join(' and ')}" }
        conflict("spec_conflict", "Two specifications on one line: #{standards.map(&:first).join(' and ')}. They are different products.", ["standard"])
      end

      Lexicon::FINISHES.each do |pattern, finish, why|
        m = pattern.match(@text)
        next unless m

        set("finish", finish, m, why)
        break
      end

      Lexicon::PROCESSES.each do |pattern, process|
        m = pattern.match(@text)
        next unless m

        set("process", process, m, "#{m[0]} as written")
        break
      end

      Lexicon::COATINGS.each do |pattern, coating|
        m = pattern.match(@text)
        next unless m

        set("coating", coating, m, "#{m[0]} as written")
        break
      end

      if (m = /\bCQ\b/.match(@text))
        set("quality", "commercial quality", m, "CQ means commercial quality, a sheet quality term, not a structural grade", confidence: 0.8, occupy: true)
      end
      if (m = Lexicon::YIELD.match(@text))
        set("yield_ksi", m[1].to_i, m, "minimum yield strength as written", occupy: true)
      end
      if (m = /\b(?:304|316)\s*\/\s*(?:304|316)L\b|\bdual\s*cert(?:ified)?\b/i.match(@text))
        @assumptions << "Dual certified stock (#{m[0]}) is one heat that meets both grades."
      end
    end

    def read_gauge_and_schedule
      if (m = Lexicon::GAUGE.match(@text))
        set("gauge", m[1].to_i, m, "a gauge number is not a thickness; it is looked up in a table by material and form", occupy: true)
      end
      if (m = Lexicon::SCHEDULE.match(@text))
        set("schedule", m[1], m, "pipe schedule as written", occupy: true)
      end
    end

    # ---- quantity ---------------------------------------------------------

    def read_quantity
      text = masked
      Lexicon::QUANTITIES.each do |pattern, unit|
        m = pattern.match(text)
        next unless m
        next if m.begin(1).positive? && @text[m.begin(1) - 1] == "-" # "A516-70 plate" is a grade, not 70 plates

        set("quantity", m[1].delete(",").to_i, m, "quantity as written", occupy: true)
        unit = m[0][/[A-Za-z]+\.?\z/].to_s.downcase.sub(/s\z/, "") if unit == :unit_as_written
        set("quantity_unit", unit || "each", m, unit ? "unit as written" : "no unit written; read as each", confidence: unit ? 0.95 : 0.8)
        @assumptions << "No quantity unit written; read as each." unless unit
        return
      end

      if (m = /\b(?:qty|quantity)\s*(?:of\s*)?(#{Lexicon::QUANTITY_WORDS.keys.join('|')})\b/i.match(text))
        set("quantity", Lexicon::QUANTITY_WORDS[m[1].downcase], m, "quantity written as a word", occupy: true)
        set("quantity_unit", "each", m, "no unit written; read as each", confidence: 0.8)
        return
      end

      m = text.to_enum(:scan, TRAILING_QTY).map { Regexp.last_match }.reverse.find do |candidate|
        next false if occupied?(candidate.begin(0)...candidate.end(0))

        previous_token = @text[0...candidate.begin(0)].split(/\s+/).last.to_s
        spaced = candidate[0].match?(/\Ax\s+\d/)
        !(spaced && previous_token.match?(/\A\d+(?:\.\d+)?\z/)) # "48 x 96" is a size, "4x10 x 25" is a quantity
      end
      return unless m

      before = @text[0...m.begin(0)].rstrip
      follows_number = before.match?(/(?:\d|"|'|ft|in)\z/i)
      set("quantity", m[1].to_i, m, "trailing x#{m[1]} read as quantity", confidence: follows_number ? 0.7 : 0.85, occupy: true)
      set("quantity_unit", "each", m, "no unit written; read as each", confidence: 0.8)
      @assumptions << "Trailing \"#{m[0]}\" is read as quantity #{m[1]}, not as a dimension." if follows_number
    end

    # ---- numbers and dimensions ------------------------------------------

    def read_dimensions
      text = masked
      elements = []
      chains = text.to_enum(:scan, CHAIN).map { Regexp.last_match }
      chains.each do |chain|
        group = []
        chain[0].to_enum(:scan, ELEMENT).each do
          e = Regexp.last_match
          abs_begin = chain.begin(0) + e.begin(1)
          abs_end = chain.begin(0) + (e.end(2) || e.end(1))
          group << element(e, abs_begin, abs_end, chain: true)
          @occupied << (abs_begin...abs_end)
        end
        elements << group
      end

      standalone = []
      masked.to_enum(:scan, STANDALONE).each do
        e = Regexp.last_match
        range = e.begin(1)...(e.end(3) || e.end(2) || e.end(1)) # the number, its unit, and its word; not trailing spaces
        next if occupied?(range)
        next if e[2].nil? && e[3].nil? && !e[1].match?(%r{/|\A\.|\A0\.}) # a bare integer with no unit or word is not a dimension

        standalone << element(e, range.begin, range.end, chain: false)
        @occupied << range
      end

      assign_dimensions(elements, standalone)
    end

    def element(match, abs_begin, abs_end, chain:)
      value = Units.parse_number(match[1])
      unit = Units.unit_of(match[2])
      suffix = (match.names.include?("3") ? nil : match[3]) if match.size > 3
      suffix ||= SUFFIX.match(@text[abs_end..])&.[](1)
      { value: value, unit: unit, suffix: suffix&.downcase, text: @text[abs_begin...abs_end].strip, chain: chain,
        raw: match[1], range: abs_begin...abs_end }
    end

    def inches(el)
      Units.to_inches(el[:value], el[:unit])
    end

    def evidence_text(el)
      suffix_text = el[:suffix] ? @text[el[:range].end..][SUFFIX, 1] : nil
      [el[:text], suffix_text].compact.join(" ")
    end

    def set_dim(field, el, why, confidence: 0.9)
      return if el.nil? || el[:value].nil?

      @fields[field] = Units.tidy(inches(el))
      @evidence[field] = { "text" => evidence_text(el), "location" => "#{@location}, chars #{el[:range].begin + 1}-#{el[:range].end}",
                           "explanation" => why }
      @confidence[field] = confidence
    end

    def feet_shorthand?(chain)
      chain.size == 2 && chain.all? { |e| e[:unit].nil? && e[:value] <= 12 && e[:value] == e[:value].to_i }
    end

    def unit_note(el)
      case el[:unit]
      when :ft then "#{el[:raw]} ft is #{Units.tidy(inches(el))} in"
      when :mm then "#{el[:raw]} mm is #{Units.tidy(inches(el))} in"
      else "#{el[:raw]} in as written"
      end
    end

    def assign_dimensions(elements, standalone)
      form = @fields["form"]
      # Suffix words settle a number wherever it sits.
      (elements.flatten + standalone).each do |el|
        case el[:suffix]
        when "thick", "thk"
          set_dim(tube_form?(form) ? "wall_in" : "thickness_in", el, "#{unit_note(el)}, written as the thickness")
        when "wall" then set_dim("wall_in", el, "#{unit_note(el)}, written as the wall")
        when "long", "lg" then set_dim("length_in", el, "#{unit_note(el)}, written as the length")
        when "wide" then set_dim("width_in", el, "#{unit_note(el)}, written as the width")
        when "dia", "dia.", "diameter", "od" then set_dim("diameter_in", el, "#{unit_note(el)}, written as the diameter")
        end
      end
      remaining = ->(list) { list.reject { |e| e[:suffix] } }

      chains = elements.map { |group| remaining.call(group) }.reject(&:empty?)
      chain = chains.max_by(&:size) || []
      loose = remaining.call(standalone)

      # Loose numbers: a fraction or decimal under one inch is a thickness or wall; a footage is a length.
      loose.each do |el|
        if el[:unit] == :ft
          set_dim("length_in", el, "#{unit_note(el)}; a footage on its own is the length")
        elsif el[:value] < 1 && el[:unit] != :ft
          field = tube_form?(form) ? "wall_in" : "thickness_in"
          set_dim(field, el, "#{el[:raw]} in, a fraction or decimal under one inch, read as the #{field == 'wall_in' ? 'wall' : 'thickness'}") unless @fields[field]
        elsif ["round bar", "pipe"].include?(form) && el[:unit] == :in
          set_dim(form == "pipe" ? "nominal_size_in" : "diameter_in", el, "#{unit_note(el)}, the #{form == 'pipe' ? 'nominal pipe size' : 'diameter'}")
        elsif tube_form?(form) && !@fields["side_a_in"]
          set_dim("side_a_in", el, "#{unit_note(el)}, the tube side")
          set_dim("side_b_in", el, "#{unit_note(el)}, square tube has equal sides")
          @assumptions << "One side given for a square tube; both sides read as #{@fields['side_a_in']} in."
        elsif el[:unit] == :in && !@fields["thickness_in"] && %w[sheet plate].include?(form)
          set_dim("thickness_in", el, "#{unit_note(el)}, read as the thickness")
        end
      end

      case form
      when "sheet", "plate", "expanded metal", nil
        chains.each { |c| assign_flat(c.dup) }
      when "flat bar", "bar"
        assign_flat_bar(chain)
      when "square tube", "rectangular tube", "tube", "round tube"
        assign_tube(chain)
      when "angle"
        assign_angle(chain)
      when "round bar", "pipe"
        chain.first(1).each { |el| set_dim(form == "pipe" ? "nominal_size_in" : "diameter_in", el, unit_note(el)) }
      end
    end

    TUBE_FORMS = ["square tube", "rectangular tube", "tube", "round tube", "pipe"].freeze

    def tube_form?(form)
      TUBE_FORMS.include?(form)
    end

    def assign_flat(chain)
      return if chain.empty?

      if chain.size >= 3 && !@fields["thickness_in"]
        t = chain.shift
        set_dim("thickness_in", t, "#{unit_note(t)}; the first of three numbers on plate is the thickness")
        @assumptions << "Three numbers with no words: read as thickness x width x length (plate convention)."
      elsif chain.size >= 3
        extra = chain.pop
        if extra[:unit].nil? && extra[:value] == extra[:value].to_i && !@fields["quantity"]
          @fields["quantity"] = extra[:value].to_i
          @evidence["quantity"] = { "text" => extra[:text], "location" => "#{@location}, chars #{extra[:range].begin + 1}-#{extra[:range].end}",
                                    "explanation" => "a third number after a sheet size is read as the quantity" }
          @confidence["quantity"] = 0.6
          @fields["quantity_unit"] ||= "each"
          conflict("quantity_or_dimension", "The trailing #{extra[:text]} could be the quantity or part of a size.", ["quantity"])
        end
      end
      return if chain.size < 2

      feet = feet_shorthand?(chain)
      w, l = chain
      if @fields["width_in"] && @fields["length_in"]
        new_w = feet ? w[:value] * 12 : inches(w)
        new_l = feet ? l[:value] * 12 : inches(l)
        if [Units.tidy(new_w), Units.tidy(new_l)] == [@fields["width_in"], @fields["length_in"]]
          @assumptions << "The size is written twice (#{@evidence['width_in']['text']} and #{@text[w[:range].begin...l[:range].end]}); both read the same."
        else
          conflict("size_conflict", "Two sizes are written: #{@fields['width_in']} x #{@fields['length_in']} in and #{Units.tidy(new_w)} x #{Units.tidy(new_l)} in.", %w[width_in length_in])
        end
        return
      end
      why = feet ? "sheet sizes under 12 with no unit are feet: #{w[:raw]} ft x #{l[:raw]} ft is #{Units.tidy(w[:value] * 12)} in x #{Units.tidy(l[:value] * 12)} in" : nil
      if feet
        @fields["width_in"] = Units.tidy(w[:value] * 12)
        @fields["length_in"] = Units.tidy(l[:value] * 12)
        %w[width_in length_in].each do |f|
          @evidence[f] = { "text" => @text[w[:range].begin...l[:range].end], "location" => "#{@location}, chars #{w[:range].begin + 1}-#{l[:range].end}",
                           "explanation" => "#{why}; the first number is the width" }
          @confidence[f] = 0.85
        end
        @rules << "Unit conversion: #{w[:raw]} ft x #{l[:raw]} ft = #{@fields['width_in']} in x #{@fields['length_in']} in"
      else
        set_dim("width_in", w, "#{unit_note(w)}; the first number is the width")
        set_dim("length_in", l, "#{unit_note(l)}; the second number is the length")
      end
    end

    def assign_flat_bar(chain)
      chain.each do |el|
        if el[:unit] == :ft && !@fields["length_in"]
          set_dim("length_in", el, "#{unit_note(el)}, the length")
        elsif el[:value] < 1 && !@fields["thickness_in"]
          set_dim("thickness_in", el, "#{unit_note(el)}, the thickness")
        elsif !@fields["width_in"]
          set_dim("width_in", el, "#{unit_note(el)}, the width")
        elsif !@fields["length_in"]
          set_dim("length_in", el, "#{unit_note(el)}, the length")
        end
      end
    end

    def assign_tube(chain)
      sides = []
      chain.each do |el|
        if el[:unit] == :ft && !@fields["length_in"]
          set_dim("length_in", el, "#{unit_note(el)}, the length")
        elsif el[:value] < 1 && !@fields["wall_in"]
          set_dim("wall_in", el, "#{unit_note(el)}, a decimal under one inch on tube is the wall")
        elsif sides.size < 2
          sides << el
        elsif !@fields["length_in"]
          set_dim("length_in", el, "#{unit_note(el)}, the third number on tube is the length")
        end
      end
      set_dim("side_a_in", sides[0], "#{unit_note(sides[0])}, the first side") if sides[0]
      set_dim("side_b_in", sides[1], "#{unit_note(sides[1])}, the second side") if sides[1]
      if sides.size == 2 && sides[0][:value] == sides[1][:value] && @fields["form"] == "tube"
        @fields["form"] = "square tube"
        @assumptions << "Equal sides read as square tube."
      end
    end

    def assign_angle(chain)
      legs = []
      chain.each do |el|
        if el[:unit] == :ft
          set_dim("length_in", el, "#{unit_note(el)}, the length")
        elsif el[:value] < 1 && legs.size >= 2
          set_dim("thickness_in", el, "#{unit_note(el)}, the leg thickness")
        elsif legs.size < 2
          legs << el
        end
      end
      set_dim("side_a_in", legs[0], "#{unit_note(legs[0])}, the first leg") if legs[0]
      set_dim("side_b_in", legs[1], "#{unit_note(legs[1])}, the second leg") if legs[1]
    end

    # ---- material and thickness resolution ---------------------------------

    def resolve_material
      if @fields["material"] == "galvanized steel" && @fields["grade"]&.match?(/\AA(36|572)/)
        @fields["material"] = "carbon steel"
        @evidence["material"]["explanation"] = "#{@fields['grade']} is a carbon steel grade; galvanized is the coating"
        @fields["coating"] = "galvanized"
      end
      return if @fields["material"]

      Lexicon::GRADE_MATERIAL.each do |material, pattern|
        m = pattern.match(@text)
        next unless m

        set("material", material, m, "#{m[0]} is a #{material} grade, so the material is #{material}", confidence: 0.9)
        return
      end
    end

    def resolve_thickness
      gauge = @fields["gauge"]
      if @fields["form"].nil? && @fields["thickness_in"] && @fields["width_in"] && @fields["length_in"]
        thick = @fields["thickness_in"]
        @fields["form"] = thick >= SHEET_PLATE_HIGH ? "plate" : "sheet"
        @evidence["form"] = { "text" => @evidence["thickness_in"]["text"], "location" => @evidence["thickness_in"]["location"],
                              "explanation" => "no form word; #{thick} in is #{@fields['form']} by the 1/4 in rule" }
        @confidence["form"] = 0.8
        @assumptions << "No product form is written; #{thick} in thick is read as #{@fields['form']} by the 1/4 in rule."
      end
      if gauge && @fields["form"].nil?
        @fields["form"] = "sheet"
        @evidence["form"] = { "text" => @evidence["gauge"]["text"], "location" => @evidence["gauge"]["location"],
                              "explanation" => "a gauge thickness with no form word is read as sheet; plate is written in fractions" }
        @confidence["form"] = 0.8
        @assumptions << "No product form is written; a gauge thickness is read as sheet."
      end
      decimal = @fields["thickness_in"] || @fields["wall_in"]
      form = @fields["form"]
      material = @fields["material"]

      if gauge
        if form == "expanded metal"
          unknown("thickness_in", "expanded metal sells by its own stock numbers; #{gauge} gauge is not in the sheet tables")
          return
        end
        if material.nil?
          cands = GaugeTable.candidates(gauge: gauge, form: form)
          unknown("thickness_in", "#{gauge} gauge has #{cands.size} readings with no material: " +
                                  cands.map { |c| "#{c[:table]} #{c[:thickness_in]}" }.join(", "))
          conflict("material_missing_with_gauge", "No material is written, and #{gauge} gauge means a different thickness for each metal.", %w[material thickness_in])
          return
        end
        lookup = GaugeTable.lookup(gauge: gauge, material: material, form: form)
        if lookup.nil?
          unknown("thickness_in", "#{gauge} gauge is not in the #{material} table used")
          conflict("gauge_not_in_table", "#{gauge} gauge is not in the #{material} gauge table. The buyer must give the thickness.", ["thickness_in"])
          return
        end
        field = tube_form?(form) ? "wall_in" : "thickness_in"
        table_value = lookup.thickness_in
        gauge_text = @evidence["gauge"]["text"]
        if decimal && (decimal - table_value).abs / table_value > GAUGE_TOLERANCE
          conflict("gauge_vs_decimal", "#{gauge_text} is #{table_value} in on the #{lookup.table} table, but #{decimal} in is also written. They differ.", [field, "gauge"])
          @fields[field] = nil
          @unknowns << { "field" => field, "reason" => "gauge and decimal disagree" }
          return
        end
        rounding = decimal ? " The written #{decimal} in rounds the table value." : ""
        @fields[field] = table_value
        @evidence[field] = { "text" => gauge_text, "location" => @evidence["gauge"]["location"],
                             "explanation" => "#{gauge} gauge on the #{lookup.table} table is #{table_value} in (#{lookup.source}).#{rounding}" }
        @confidence[field] = decimal ? 0.95 : 0.9
        @rules << "Gauge table: #{lookup.table}, #{gauge} ga = #{table_value} in"
        if lookup.alternative
          @assumptions << "Published tables differ for #{gauge} gauge #{lookup.table}: #{table_value} in here, #{lookup.alternative[:value]} in in #{lookup.alternative[:source]}."
          conflict("gauge_table_gap", "Published tables differ for #{gauge} gauge #{material}: #{table_value} in or #{lookup.alternative[:value]} in.", [field])
        end
      elsif decimal && material && (form == "sheet" || form.nil?)
        near = GaugeTable::TABLES[GaugeTable.table_for(material: material, form: form) || ""]&.find do |_g, v|
          diff = (decimal - v).abs / v
          diff > GAUGE_TOLERANCE && diff <= NEAR_GAUGE
        end
        if near
          g, v = near
          @assumptions << "#{decimal} in is written as a decimal. #{g} gauge #{material} is #{v} in, #{((v - decimal) / decimal * 100).round(1)}% different."
          conflict("decimal_near_gauge", "#{decimal} in is written. #{g} gauge #{material} is #{v} in. Is #{decimal} in exact, or is #{g} gauge acceptable?", ["thickness_in"])
        end
      end
    end

    # ---- conflicts the research names ------------------------------------

    def check_conflicts
      form = @fields["form"]
      std = @fields["standard"].to_s
      grade = @fields["grade"].to_s

      if std.start_with?("A53") && ["square tube", "rectangular tube"].include?(form)
        conflict("shape_vs_spec", "A53 is round pipe only. #{form} is A500 or A513.", %w[form standard])
      end
      if @fields["yield_ksi"] && grade == "A36" && @fields["yield_ksi"] > 36
        conflict("strength_mismatch", "A36 guarantees 36 ksi minimum yield, but #{@fields['yield_ksi']} ksi is required. That implies A572 Grade 50 or dual-certified plate.", %w[grade yield_ksi])
      end
      if @fields["quality"] && grade.match?(/\AA36/)
        conflict("spec_conflict", "CQ (commercial quality) and A36 are different specifications.", %w[quality grade])
      end
      if std == "A366"
        conflict("obsolete_spec", "A366 is an older cold rolled sheet specification. Current specs are the A1008 family.", ["standard"])
      end
      t = @fields["thickness_in"]
      if t && %w[sheet plate].include?(form) && t >= SHEET_PLATE_LOW && t < SHEET_PLATE_HIGH
        @assumptions << "#{t} in is sheet by the 1/4 in rule and plate by the 3 mm rule; the buyer wrote #{form}."
        conflict("sheet_plate_boundary", "#{t} in sits between the 3 mm and 1/4 in sheet/plate lines. Hot rolled plate, or cold rolled sheet?", ["form"])
      end
      if tube_form?(form) && form != "pipe" && @fields["standard"].nil? && @fields["standards"].nil?
        conflict("tube_spec_missing", "No tube specification is written. Structural (A500), mechanical (A513), welded or seamless?", ["standard"])
      end
      if @fields["material"] == "galvanized steel" && @fields["coating"].to_s != "galvanized coating weight" && form == "sheet"
        conflict("coating_weight_missing", "Galvanized sheet needs a coating weight, for example G60 or G90.", ["coating"])
      end
      wrought = %w[sheet plate flat\ bar bar round\ bar angle channel].include?(form) || tube_form?(form)
      if @fields["material"] == "aluminum" && @fields["temper"].nil? && @fields["grade"] && wrought && !@fields["grade"].start_with?("P")
        conflict("temper_missing", "Aluminum temper is part of the grade and is not written.", ["temper"])
      end
      if @fields["material"] == "stainless steel" && form == "sheet" && @fields["finish"].nil?
        @assumptions << "Finish is not stated. 2B is the usual mill finish for stainless sheet."
      end
      if @fields["standard"].nil? && @fields["standards"].nil? && @fields["material"] == "stainless steel" && %w[sheet plate].include?(form)
        @assumptions << "ASTM A240 is the usual specification family for stainless sheet and plate. It is not written."
      end
    end

    REQUIRED = {
      "sheet" => %w[material thickness_in width_in length_in quantity],
      "plate" => %w[material thickness_in width_in length_in quantity],
      "expanded metal" => %w[material thickness_in width_in length_in quantity],
      "flat bar" => %w[material width_in thickness_in length_in quantity],
      "bar" => %w[material width_in thickness_in length_in quantity],
      "square tube" => %w[material side_a_in side_b_in wall_in length_in quantity],
      "rectangular tube" => %w[material side_a_in side_b_in wall_in length_in quantity],
      "tube" => %w[material side_a_in wall_in length_in quantity],
      "round tube" => %w[material diameter_in wall_in length_in quantity],
      "round bar" => %w[material diameter_in length_in quantity],
      "pipe" => %w[material nominal_size_in schedule length_in quantity],
      "angle" => %w[material side_a_in side_b_in thickness_in length_in quantity],
      "hex-head bolt" => %w[part_number quantity],
      "abrasive" => %w[material grade quantity quantity_unit],
      "ingot" => %w[material grade quantity quantity_unit],
      "sow" => %w[material grade quantity quantity_unit]
    }.freeze

    def note_unknowns
      form = @fields["form"]
      unknown("form", "no product form is written (sheet, plate, bar, tube, pipe)") if form.nil?
      unknown("material", "no material is written") if @fields["material"].nil? && !@fields["part_number"] && !@fields["part_family"]
      (REQUIRED[form] || %w[material quantity]).each do |field|
        next if @fields[field]

        unknown(field, "#{field.sub('_in', '').tr('_', ' ')} is not written") unless @unknowns.any? { |u| u["field"] == field }
      end
    end
  end
end
