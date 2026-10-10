module CatalogMatch
  # Reads one buyer description into named fields with fixed rules. Every field
  # records the words it came from and why it was read that way. Words the rules
  # do not understand are kept in #unknown_words so client memory can learn them.
  #
  # Client terms (from ClientMemory) fill only fields the text did not state
  # itself; the buyer's explicit words always win.
  class DescriptionReader
    # notes are things the rep should see; questions block a confident match.
    Reading = Struct.new(:text, :fields, :part_numbers, :unknown_words, :notes, :questions, :remembered_term, keyword_init: true) do
      def [](name) = fields[name.to_s]&.fetch("value")
      def set?(name) = fields.key?(name.to_s)
      def product_fields = fields.except("quantity", "quantity_unit")
    end

    NUMBER = %r{\d+\s*-\s*\d+/\d+|\d+\s+\d+/\d+|\d+/\d+|\d*\.\d+|\d+}
    INCH = /(?:"|”|''|\s*in(?:ch(?:es)?)?\b\.?)/i
    FOOT = /(?:'|’|\s*f(?:ee)?t\b\.?|\s*foot\b)/i

    GRADES = [
      [ /\b304\s*\/\s*304\s*l\b/i, "304/304L", "stainless steel" ],
      [ /\b316\s*\/\s*316\s*l\b/i, "316/316L", "stainless steel" ],
      [ /\b304\s*l\b/i, "304L", "stainless steel" ],
      [ /\b316\s*l\b/i, "316L", "stainless steel" ],
      [ /\b304\b/, "304", "stainless steel" ],
      [ /\b316\b/, "316", "stainless steel" ],
      [ /\b5052\b/, "5052", "aluminum" ],
      [ /\b6061\b/, "6061", "aluminum" ],
      [ /\ba\s*-?\s*36\s*\/\s*a\s*-?\s*572(?:\s*-?\s*(?:gr\.?\s*)?50)?\b/i, "A36/A572-50", "carbon steel" ],
      [ /\ba\s*-?\s*572(?:\s*-?\s*(?:gr\.?|grade)?\s*50)?\b/i, "A572-50", "carbon steel" ],
      [ /\ba\s*-?\s*516\s*-?\s*(?:gr\.?\s*)?70\b/i, "A516-70", "carbon steel" ],
      [ /\ba\s*-?\s*36\b/i, "A36", "carbon steel" ]
    ].freeze

    # RudCo's abrasives and aluminum alloys. Shot and grit sizes follow SAE J827
    # (S-330 is 0.033 in); "G90" is a galvanized coating, not a grit size.
    ABRASIVE_GRADES = [
      [ /\b(S)\s*-?\s*(70|110|170|230|280|330|390|460|550|660|780|930)\b|\b(G)\s*-?\s*(10|12|14|16|18|25|40|50|80|120)\b/i, nil ],
      [ /\b(\d{2,3})\s*grit\b/i, "grit" ],
      [ /(\+?\d{1,3}(?:\/\d{1,3})?)\s*mesh\b/i, "mesh" ]
    ].freeze

    ALLOY_GRADES = [
      [ /\bP\s*-?\s*1020\s*A?\b/i, "P1020" ],
      [ /\bA\s*-?\s*356(?:\.[0-2])?\b/i, "A356" ],
      [ /\b356(?:\.[01])?\b/, "356" ],
      [ /\b319\.1\b|\b319\b(?=.*\b(?:alum|ingot|alloy)\w*)/i, "319.1" ],
      [ /\b332\.1\b|\b332\b(?=.*\b(?:alum|ingot|alloy)\w*)/i, "332.1" ]
    ].freeze

    ABRASIVE_MATERIALS = [
      [ /\bstainless(?:\s+steel)?\s+shot\b/i, "stainless steel shot" ],
      [ /\bstainless(?:\s+steel)?\s+grit\b/i, "stainless steel grit" ],
      [ /\b(?:cast\s+)?steel\s+shot\b|\bshot\s+blast(?:ing)?\s+media\b/i, "steel shot" ],
      [ /\bsteel\s+grit\b/i, "steel grit" ],
      [ /\bwhite\s+alum(?:inum)?\s+oxide\b/i, "white aluminum oxide" ],
      [ /\b(?:brown\s+)?alum(?:inum|inium)?\s+oxide\b|\balox\b|\bfused\s+alumina\b/i, "aluminum oxide" ],
      [ /\bgarnet\b/i, "garnet" ],
      [ /\bglass\s+beads?\b/i, "glass bead" ],
      [ /\bcrushed\s+glass\b/i, "crushed glass" ],
      [ /\bcorn\s*cob\b/i, "corn cob" ],
      [ /\bcopper\s+slag\b/i, "copper slag" ]
    ].freeze

    TEMPERS = { /\bt\s*651\b/i => "T651", /\bt6\b/i => "T6", /\bh\s*32\b/i => "H32", /\bh\s*34\b/i => "H34" }.freeze

    STANDARDS = /\b(?:asme\s+)?(s?a)\s*-?\s*(240|500|513|53|276|312|1008|653|554|366)\b(?:\s*(?:gr\.?|grade)\s*([bc](?:\s*\/\s*c)?))?|\bb\s*-?\s*(209|221)\b/i

    MATERIALS = [
      [ /\bstainless(?:\s+steel)?\b|\bs\/s\b|\bss\b/i, "stainless steel" ],
      [ /\bgalv(?:anized|\.)?\b|\bg90\b|\bg60\b/i, "galvanized steel" ],
      [ /\balum(?:inum|inium|\.)?\b/i, "aluminum" ],
      [ /\bcold[\s-]*rolled\b|\bhot[\s-]*rolled\b|\bc\.?r\.?\b|\bh\.?r\.?\b|\bmild\s+steel\b|\bcarbon(?:\s+steel)?\b|\bm\.?s\.?\b/i, "carbon steel" ]
    ].freeze

    FORMS = [
      [ /\bsq(?:uare|\.)?\s*(?:tube|tubing|tubes)\b|\b(?:tube|tubing|tubes)\b/i, "square tube" ],
      [ /\bsheets?\b|\bshts?\b/i, "sheet" ],
      [ /\bplates?\b|\bplt\b|\bpl\b/i, "plate" ],
      [ /\bangles?\b|\bangle\s+iron\b/i, "angle" ],
      [ /\bflat\s*bars?\b|\bflats?\b|\bstrips?\b/i, "flat bar" ],
      [ /\br(?:oun)?d\.?\s*bars?\b|\brods?\b|\bround\b/i, "round bar" ],
      [ /\bpipes?\b/i, "pipe" ],
      [ /\bbolts?\b/i, "bolt" ],
      [ /\b(?:(?:hex\s+)?cap\s+|machine\s+)?screws?\b/i, "screw" ],
      [ /\bnuts?\b/i, "nut" ],
      [ /\bwashers?\b/i, "washer" ],
      [ /\bingots?\b|\bt[\s-]?bars?\b|\bpigs?\b/i, "ingot" ],
      [ /\bsows?\b/i, "sow" ],
      [ /\b(?:blast(?:ing)?\s+)?(?:media|abrasives?)\b/i, "abrasive" ]
    ].freeze

    FINISHES = [
      [ /\b2\s*b\b/i, "2B" ],
      [ /#\s*4\b|\bno\.?\s*4\b|\bbrushed\b/i, "#4" ],
      [ /\bhrap\b|#\s*1\b|\bno\.?\s*1\b/i, "HRAP #1" ],
      [ /\bmill\s+finish\b/i, "mill" ],
      [ /\bcad(?:mium)?(?:[\s-]*plated)?\b/i, "cadmium plated" ]
    ].freeze

    QUANTITY_PATTERNS = [
      /\b(?:qty|quantity)\s*[:=]?\s*(\d[\d,]*)\b/i,
      /\b(\d{1,3}(?:,\d{3})+|\d+)\s*(lbs?|pounds|tons?|bulk\s+bags|super\s*sacks?|bags|sacks|drums|pallets|skids|truckloads?)\b/i,
      /\b(\d+)\s*(pcs?|pieces?|ea|each|sheets|shts|plates|lengths|lgths|sticks|bars|units)\b/i,
      # "4x8 x4", "x40 Buy America": a space before the x and none after it.
      /\sx(\d+)\b(?!\s*["'\/.x×])/i,
      /\b(?:need|send|quote|price)\s+(\d+)\b/i
    ].freeze

    FILLER_WORDS = %w[
      a an and are as at be by can for from have i in is it long me need of on or our per please price pricing
      quote send thick the to us w we with you your thanks thank hi hello wall lg lgth length size type grade gr
      x by each ea pc pcs qty quantity ft in inch inches feet foot steel delivery deliver asap rfq item items
      min max yield ksi cert certs certified mtr compliant tested equivalent or astm asme
    ].freeze

    def self.read(text, client_terms: [], given: {})
      new(text, client_terms, given).read
    end

    def initialize(text, client_terms, given = {})
      @original = text.to_s.strip
      @work = @original.dup
      @client_terms = client_terms
      @given = (given || {}).to_h.stringify_keys
      @fields = {}
      @part_numbers = []
      @notes = []
      @questions = []
    end

    def read
      read_part_numbers
      read_feet_dimensions
      read_lengths
      read_bolt_specs
      read_gauge
      read_explicit_thickness
      read_grade_and_material
      read_standards
      read_tempers
      read_process_and_schedule
      read_quantity
      read_forms
      read_finishes
      read_dimensions
      apply_given_spec
      apply_client_terms
      infer_material_from_grade

      Reading.new(text: @original, fields: @fields, part_numbers: @part_numbers.uniq,
                  unknown_words: unknown_words, notes: @notes, questions: @questions,
                  remembered_term: @remembered_term)
    end

    private

    def read_part_numbers
      consume(/\bRC-[A-Z0-9]+(?:-[A-Z0-9]+)+\b/i) { |match| @part_numbers << match[0].upcase }
      # AN/MS/NAS standard parts: AN3-13A, an3 dash 13a, AN315-3L, MS35206-245.
      consume(/\b(AN|MS|NAS)\s*(\d{1,6})\s*(?:-|\s|dash)\s*([A-Z]{0,2}\d{1,3})\s*([A-Z]{1,2})?\b/i) do |match|
        @part_numbers << "#{match[1].upcase}#{match[2]}-#{match[3]}#{match[4]&.upcase}"
      end
    end

    # "8 feet x 20 feet" is a width and a length, not two lengths.
    def read_feet_dimensions
      consume(/(#{NUMBER})\s*#{FOOT}\s*[x×]\s*(#{NUMBER})\s*#{FOOT}/io) do |match|
        width, length = [ parse_number(match[1]), parse_number(match[2]) ].sort
        set("width", width * 12, match[0], "#{format_in(width)} ft is #{format_in(width * 12)} in")
        set("length", length * 12, match[0], "#{format_in(length)} ft is #{format_in(length * 12)} in")
      end
    end

    def read_lengths
      consume(/(#{NUMBER})\s*#{FOOT}\s*(?:long|lg|lengths?)?/io) do |match|
        feet = parse_number(match[1])
        set("length", feet * 12, match[0], "#{match[1]} ft is #{format_in(feet * 12)} in")
      end
      consume(/(#{NUMBER})\s*(?:#{INCH})?\s*(?:long|lg)\b/io) do |match|
        set("length", parse_number(match[1]), match[0], "length written in inches")
      end
    end

    def read_bolt_specs
      # Unified thread sizes: 10-32, 1/4-20, 6-32, 1/2-13.
      consume(%r{(?<![\w./-])((?:\d+/\d+|#?\d{1,2})-\d{2})(?![\w./-])}) do |match|
        set("thread", match[1], match[0], "thread size #{match[1]}")
      end
      consume(/\b(un)?drilled\b/i) do |match|
        set("drilled", match[1].nil?, match[0], match[1] ? "shank not drilled" : "drilled shank, for a cotter pin")
      end
      consume(/(#{NUMBER})\s*(?:#{INCH})?\s*grip\b|\bgrip\s*(?:of\s*)?(#{NUMBER})\s*(?:#{INCH})?/io) do |match|
        set("grip", parse_number(match[1] || match[2]), match[0], "grip length in inches")
      end
    end

    def read_gauge
      consume(/(?:\b|#)(\d{1,2})\s*(?:ga|gauge|gage)\b\.?|\b(?:ga|gauge|gage)\.?\s*(\d{1,2})\b/i) do |match|
        gauge = (match[1] || match[2]).to_i
        set("gauge", gauge, match[0], "gauge #{gauge}; its thickness depends on the material's gauge table")
      end
    end

    def read_explicit_thickness
      consume(/(#{NUMBER})\s*(?:#{INCH})?\s*(?:thick|thk|wall|wt)\b/io) do |match|
        set("thickness", parse_number(match[1]), match[0], "thickness written as #{match[1]} in")
      end
    end

    def read_grade_and_material
      read_abrasives_and_alloys
      GRADES.each do |pattern, grade, material|
        next if set?("grade")

        consume(pattern) do |match|
          set("grade", grade, match[0], "grade #{grade}")
          @grade_material = [ material, match[0] ]
        end
      end
      MATERIALS.each do |pattern, material|
        next if set?("material")

        consume(pattern) { |match| set("material", material, match[0], "#{match[0].strip} means #{material}") }
      end
    end

    def read_abrasives_and_alloys
      ABRASIVE_MATERIALS.each do |pattern, material|
        next if set?("material")

        consume(pattern) do |match|
          set("material", material, match[0], "#{match[0].strip} is #{material} blast media")
          set("form", "abrasive", match[0], "#{material} is sold as blast media", source: "rule")
        end
      end
      ABRASIVE_GRADES.each do |pattern, kind|
        next if set?("grade")

        consume(pattern) do |match|
          letter, number = kind ? [] : [ match[1] || match[3], match[2] || match[4] ]
          grade = case kind
                  when "grit" then "#{match[1]} grit"
                  when "mesh" then "#{match[1]} mesh"
                  else "#{letter.upcase}-#{number}"
                  end
          explanation = kind ? "size #{grade}" : "SAE J827 size #{grade}"
          set("grade", grade, match[0], explanation)
          if kind.nil?
            shot_or_grit = letter.casecmp?("S") ? "shot" : "grit"
            @grade_material = [ "steel #{shot_or_grit}", match[0] ]
            set("form", "abrasive", match[0], "#{grade} is a #{shot_or_grit} size", source: "rule")
          end
        end
      end
      ALLOY_GRADES.each do |pattern, grade|
        next if set?("grade")

        consume(pattern) do |match|
          set("grade", grade, match[0], "aluminum alloy #{grade}")
          @grade_material = [ "aluminum", match[0] ]
        end
      end
    end

    def read_standards
      consume(STANDARDS) do |match|
        if match[4]
          set_standard("B#{match[4]}", match[0])
        else
          prefix = match[1].upcase
          spec = "#{prefix}#{match[2]}"
          set_standard(spec, match[0])
          next if @fields["standard"].key?("also")

          set("grade", "A500", match[0], "A500 structural tube grade") if match[2] == "500"
          set("grade", "A513", match[0], "A513 mechanical tube") if match[2] == "513"
        end
      end
    end

    def set_standard(spec, text)
      if set?("standard") && @fields["standard"]["value"] != spec
        first = @fields["standard"]["value"]
        @questions << "The line names two different specs, #{first} and #{spec}. Which one governs?"
        @fields["standard"]["also"] = spec
        @fields.delete("grade") if @fields.dig("grade", "text") == @fields["standard"]["text"]
        return
      end
      set("standard", spec, text, "specification #{spec}")
    end

    def read_tempers
      TEMPERS.each do |pattern, temper|
        next if set?("temper")

        consume(pattern) { |match| set("temper", temper, match[0], "temper #{temper}") }
      end
    end

    def read_forms
      consume(/\bL\s*(#{NUMBER})\s*[x×]\s*(#{NUMBER})\s*[x×]\s*(#{NUMBER})/io) do |match|
        set("form", "angle", match[0], "L means angle")
        set("size_a", parse_number(match[1]), match[0], "angle leg")
        set("size_b", parse_number(match[2]), match[0], "angle leg")
        set("thickness", parse_number(match[3]), match[0], "angle thickness")
      end
      if !set?("form") && set?("schedule")
        set("form", "pipe", @fields["schedule"]["text"], "a pipe schedule means the item is pipe", source: "rule")
      end
      FORMS.each do |pattern, form|
        next if set?("form")

        consume(pattern) { |match| set("form", form, match[0], "#{match[0].strip} means #{form}") }
      end
    end

    def read_finishes
      FINISHES.each do |pattern, finish|
        next if set?("finish")

        consume(pattern) { |match| set("finish", finish, match[0], "finish #{finish}") }
      end
    end

    def read_process_and_schedule
      consume(/\bsch(?:edule|\.)?\s*(\d+)\b/i) { |match| set("schedule", match[1], match[0], "pipe schedule #{match[1]}") }
      consume(/\bsmls\b|\bseamless\b/i) { |match| set("process", "seamless", match[0], "seamless") }
      consume(/\bwelded\b|\berw\b/i) { |match| set("process", "welded", match[0], "welded") }
    end

    def read_quantity
      QUANTITY_PATTERNS.each do |pattern|
        break if set?("quantity")

        consume(pattern) do |match|
          next if set?("quantity")

          set("quantity", match[1].delete(",").to_i, match[0].strip, "quantity #{match[1]}")
          unit = match.size > 2 ? match[2] : nil
          @fields["quantity_unit"] = { "value" => unit.downcase.squish, "text" => unit } if unit
        end
      end
      return if set?("quantity")

      # "4x10 x 25" ends in a count; "48 x 96" ends in a size. Only read the
      # trailing number as a count when a full size already comes before it.
      trailing = @work.match(/\s[x×]\s+(\d+)\s*\z/i)
      return unless trailing && @work[0...trailing.begin(0)].match?(/\d\s*[x×]\s*\d[^\s]*\s*\z/i)

      set("quantity", trailing[1].to_i, trailing[0].strip, "trailing x #{trailing[1]} after the size read as the quantity")
      @work[trailing.begin(0)...trailing.end(0)] = " " * (trailing.end(0) - trailing.begin(0))
    end

    # Numbers left after the labeled ones: "4x8", "48 x 96", "2x2", "3/16", "2in".
    def read_dimensions
      consume(/(#{NUMBER})\s*(#{INCH}|#{FOOT})?\s*[x×]\s*(#{NUMBER})\s*(#{INCH}|#{FOOT})?(?:\s*[x×]\s*(#{NUMBER})\s*(#{INCH})?)?/io) do |match|
        numbers = [ match[1], match[3], match[5] ].compact.map { |value| parse_number(value) }
        units = [ match[2], match[4], match[6] ]
        assign_dimension_group(numbers, units, match[0])
      end
      consume(/(?<![\w.\/-])(#{NUMBER})\s*(#{INCH})?(?![\w\/-])/io) do |match|
        assign_single_number(parse_number(match[1]), match[0])
      end
    end

    def assign_dimension_group(numbers, units, text)
      form = value_of("form")
      if %w[square tube angle].include?(form) || (numbers.size >= 2 && numbers[0] == numbers[1] && numbers[0] <= 6)
        set("size_a", numbers[0], text, "outside size #{format_in(numbers[0])} in")
        set("size_b", numbers[1], text, "outside size #{format_in(numbers[1])} in")
        set("thickness", numbers[2], text, "wall #{numbers[2]} in") if numbers[2] && !set?("thickness")
        return
      end

      if numbers.size == 3
        smallest = numbers.min
        trailing_count = units[2].nil? && numbers[2] == numbers[2].to_i && numbers[2] == smallest &&
                         numbers[0] >= 4 && numbers[1] >= 4
        if trailing_count
          unless set?("quantity")
            set("quantity", numbers[2].to_i, text, "trailing x#{numbers[2].to_i} read as the quantity")
            @notes << "Read the trailing \"x#{numbers[2].to_i}\" as the quantity. Confirm it is not part of the size."
          end
          numbers = numbers.first(2)
        elsif smallest <= 3 && numbers.count(smallest) == 1
          set("thickness", smallest, text, "the smallest number, #{format_in(smallest)} in, is the thickness")
          numbers = numbers - [ smallest ]
        end
      end

      width, length = numbers.first(2).sort
      in_feet = units.first(2).any? { |unit| unit.to_s.match?(FOOT) } ||
                (units.first(2).none? && width <= 12 && length <= 20 && form != "flat bar")
      if in_feet
        set("width", width * 12, text, "#{format_in(width)} x #{format_in(length)} read as feet: #{format_in(width * 12)} x #{format_in(length * 12)} in")
        set("length", length * 12, text, "#{format_in(length)} ft is #{format_in(length * 12)} in")
      else
        set("width", width, text, "width #{format_in(width)} in")
        set("length", length, text, "length #{format_in(length)} in") unless set?("length")
      end
    end

    def assign_single_number(value, text)
      case value_of("form")
      when "round bar", "bolt" then set("diameter", value, text, "diameter #{format_in(value)} in")
      when "pipe" then set("nps", value, text, "nominal pipe size #{format_in(value)} in")
      when "square tube"
        if set?("size_a")
          set("thickness", value, text, "wall #{value} in") if value < 1
        else
          set("size_a", value, text, "outside size #{format_in(value)} in")
          set("size_b", value, text, "square tube, so both sides are #{format_in(value)} in", source: "rule")
        end
      when "flat bar"
        if !set?("width") && (set?("thickness") || value >= 0.5)
          set("width", value, text, "flat bar width #{format_in(value)} in")
        elsif !set?("thickness")
          set("thickness", value, text, "thickness #{format_in(value)} in")
        end
      else
        set("thickness", value, text, "thickness #{format_in(value)} in") if value <= 4 && !set?("gauge")
      end
    end

    def apply_client_terms
      apply_client_phrase
      @client_terms.each do |term|
        next if term.field_values.empty?

        pattern = /(?<![\w])#{Regexp.escape(term.term).gsub('\ ', '\s*')}(?![\w])/i
        # A taught term can be words the rules also read ("16 ga"), so look in
        # the original text; memory still fills only fields the text left open.
        found = @original.match(pattern)
        next unless found

        consume(pattern) { nil } if @work.match?(pattern)
        term.field_values.each do |field, value|
          # A confirmed meaning replaces the generic reading of the same words
          # ("0.060 in" confirmed as 16 ga), never a reading of other words.
          @fields.delete(field) if set?(field) && same_words?(@fields[field]["text"], found[0])
          next if set?(field)

          set(field, value, found[0], "#{term.explanation_prefix} \"#{found[0]}\" means #{field} #{value}", source: "client_memory")
        end
      end
    end

    def same_words?(field_text, term_text)
      a = field_text.to_s.downcase.gsub(/\s+/, "")
      b = term_text.to_s.downcase.gsub(/\s+/, "")
      a.present? && b.present? && (a.include?(b) || b.include?(a))
    end

    GIVEN_TEXT_FIELDS =%w[material grade temper form finish standard schedule process thread].freeze
    GIVEN_NUMBER_FIELDS = %w[thickness width length diameter nps gauge grip size_a size_b quantity].freeze

    # A normalized spec from RFQ processing fills only fields the text did not
    # state; the buyer's own words still win.
    def apply_given_spec
      part_number = @given["part_number"].to_s.strip
      @part_numbers << part_number.upcase if part_number.present? && @part_numbers.empty?
      @given.each do |name, given|
        # A plain value comes from RFQ processing; a hash carries its own
        # quoted words and source (the LLM reader).
        value, text, explanation, source = unpack_given(name, given)
        next if value.nil? || value.to_s.strip.empty?

        if GIVEN_TEXT_FIELDS.include?(name)
          set(name, value.to_s, text, explanation, source: source)
        elsif GIVEN_NUMBER_FIELDS.include?(name)
          number = Float(value.to_s, exception: false)
          next if number.nil?

          number = number.to_i if %w[gauge quantity].include?(name)
          set(name, number, text, explanation, source: source)
        end
      end
    end

    def unpack_given(name, given)
      if given.is_a?(Hash)
        [ given["value"], given["text"].presence || given["value"].to_s,
          given["explanation"].presence || "#{name} from #{given['source'] || 'processing'}", given["source"] || "rfq_processing" ]
      else
        [ given, given.to_s, "#{name} from RFQ processing", "rfq_processing" ]
      end
    end

    # A remembered phrase points at one part number. It applies only when the
    # whole request, minus its quantity, is that phrase, so extra words such as
    # a different grade are never overridden by memory.
    def apply_client_phrase
      return if @part_numbers.any?

      request = @original.dup
      quantity_text = @fields.dig("quantity", "text")
      request = request.sub(quantity_text, " ") if quantity_text.present?
      request = request.squish.downcase
      term = @client_terms.find { |candidate| candidate.part_number.present? && candidate.term == request }
      return unless term

      @part_numbers << term.part_number.upcase
      @remembered_term = term
      @notes << "#{term.explanation_prefix} this exact request means #{term.part_number}."
    end

    def infer_material_from_grade
      return unless @grade_material

      material, text = @grade_material
      # "stainless S-330" names stainless shot, not plain steel shot.
      if material.start_with?("steel ") && value_of("material") == "stainless steel"
        @fields["material"].merge!("value" => "stainless #{material}",
                                   "explanation" => "stainless with a shot or grit size means stainless #{material}")
        return
      end
      return if set?("material")

      set("material", material, text, "grade #{value_of('grade')} is a #{material} grade", source: "rule")
    end

    def unknown_words
      @work.scan(/[a-z][a-z0-9.\/-]*|\d+[a-z]+[a-z0-9]*/i)
           .map { |word| word.downcase.sub(/[^a-z0-9]+\z/, "") }
           .reject { |word| word.length < 2 || FILLER_WORDS.include?(word) }
           .uniq
    end

    def set?(name) = @fields.key?(name)
    def value_of(name) = @fields[name]&.fetch("value")

    # The first reading of a field wins; later, weaker rules never overwrite it.
    def set(name, value, text, explanation, source: "text")
      return if @fields.key?(name)

      @fields[name] ={ "value" => value, "text" => text.to_s.strip, "explanation" => explanation, "source" => source }
    end

    # Runs the block on each match, then blanks the matched words so later rules
    # and the unknown-word list do not see them again.
    def consume(pattern)
      @work.to_enum(:scan, pattern).map { Regexp.last_match }.each do |match|
        yield match
        @work[match.begin(0)...match.end(0)] = " " * (match.end(0) - match.begin(0))
      end
    end

    def parse_number(raw)
      text = raw.to_s.strip
      if (parts = text.match(%r{\A(\d+)\s*[-\s]\s*(\d+)/(\d+)\z}))
        parts[1].to_f + parts[2].to_f / parts[3].to_f
      elsif (parts = text.match(%r{\A(\d+)/(\d+)\z}))
        parts[1].to_f / parts[2].to_f
      else
        text.to_f
      end
    end

    def format_in(value)
      value == value.to_i ? value.to_i.to_s : value.round(4).to_s
    end
  end
end
