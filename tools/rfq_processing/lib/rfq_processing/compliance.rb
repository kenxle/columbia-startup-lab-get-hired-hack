# frozen_string_literal: true

module RfqProcessing
  # Hidden requirements: the certifications and origin rules an RFQ line states
  # outright, implies through its spec, or carries from context (ship-to, funding,
  # attachments). Source: Ken's domain research, section 3 (summary table 3.1 and
  # detail 3.2) plus the worked examples T16 to T25. Every flag quotes the exact
  # text or spec value that triggered it and repeats the research's confidence.
  # A flag means "this implies X because of Y; confirm", never a legal ruling.
  # The strength contradiction in T16 (A36 with 50 ksi) is the parser's job, not
  # a compliance flag.
  module Compliance
    SOURCE = "docs/research/20261010.01_rfq_sharper_angle/research_domain_rules.md, section 3"

    LABELS = {
      "mtr" => "Mill test report required",
      "en10204_3_1" => "EN 10204 3.1 certificate required",
      "en10204_3_2" => "EN 10204 3.2 certificate (witnessed) required",
      "dfars" => "DFARS specialty metals clause",
      "buy_america" => "Buy America / BABA domestic steel",
      "origin" => "Country of origin / melt location",
      "itar" => "ITAR / export-controlled data",
      "pmi" => "Positive material identification (PMI)",
      "nace" => "NACE MR0175 sour service",
      "asme_sa" => "ASME SA code material",
      "coa" => "Certificate of analysis (COA) required",
      "reach" => "REACH compliance statement required",
      "rohs" => "RoHS compliance statement required"
    }.freeze

    ORDER = LABELS.keys.freeze
    TRIGGER_RANK = { "stated" => 0, "implied" => 1, "context" => 2 }.freeze

    # "3.1" and "3.2" count only as standalone tokens: not "3.125", not "13.1".
    THREE_ONE = /(?<![\d.])3\.1(?!\.?\d)/
    THREE_TWO = /(?<![\d.])3\.2(?!\.?\d)/
    EN_10204 = /\bEN\s*10204\b/i
    US = /(?:USA\b|US\b|U\.S\.A\.?|U\.S\.|United\s+States\b)/i

    # Triggers inside the line, from the 3.1 table. Patterns inside each list are
    # in priority order: the first one that matches supplies the evidence.
    STATED = [
      ["mtr", [
        /\bMTRs?\b/i,
        /\bmill\s+test\s+(?:report|cert)s?\b/i,
        /\bmill\s+cert(?:s|ificates?|ifications?)?\b/i,
        /\bcert(?:s|ificates?|ifications?)?\b(?!\s+of\s+(?:analysis|conformance|compliance))/i,
        THREE_ONE
      ]],
      ["en10204_3_2", [
        /\bEN\s*10204[\s,:;-]*(?:type\s*)?3\.2(?!\.?\d)/i,
        THREE_TWO,
        /\bwitnessed\b/i
      ]],
      ["en10204_3_1", [
        /\bEN\s*10204[\s,:;-]*(?:type\s*)?3\.1(?!\.?\d)/i,
        THREE_ONE
      ]],
      ["dfars", [
        /\bDFARS?\b(?:\s+252\.225-7009)?/i,
        /\bspecialty\s+metals?\b/i,
        /\bqualifying\s+country\b/i
      ]],
      ["origin", [
        /\bdomestic\b(?:\s+\w+){0,2}\s+only\b/i,
        /\bno\s+China\b/i,
        /\bmelted\s+and\s+(?:rolled|poured)\s+in\s+(?:the\s+)?#{US}/i,
        /\bmelt(?:ed)?\s+and\s+pour(?:ed)?\b/i,
        /\bmelted\s+(?:in\s+)?(?:the\s+)?#{US}/i,
        /\bmill\s+origin\b/i,
        /\bcountry\s+of\s+origin\b/i
      ]],
      ["buy_america", [
        /\bBuy[\s-]+American?\b/i,
        /\bBABA\b/,
        /\b23\s*CFR\s*635\.410\b/i,
        /\bmelted\s+and\s+manufactured\s+in\s+(?:the\s+)?#{US}/i,
        /\bAmerican[\s-]+made\b/i,
        /\bdomestic\b(?!(?:\s+\w+){0,2}\s+only\b)/i
      ]],
      ["itar", [
        /\bITAR\b/i,
        /\bexport[\s-]+control(?:led)?\b/i
      ]],
      ["pmi", [
        /\b100\s*%\s*PMI\b/i,
        /\bPMI\b/i,
        /\bXRF[\s-]+verif(?:ied|ication)\b/i
      ]],
      ["nace", [
        /\bNACE(?:\s+MR[\s-]?0175)?\b/i,
        /\bMR[\s-]?0175\b/i,
        /\bISO\s*15156\b/i,
        /\bsour[\s-]+service\b/i,
        /\bH2S\b/i,
        /\bHIC\b/i
      ]],
      ["asme_sa", [
        /\bSA[\s-]?\d{3,4}[A-Z]?\b/i,
        /\bASME\b/i,
        /\bcode\s+material\b/i,
        /\bU[\s-]?stamp\b/i
      ]],
      # Paperwork RudCo already sells with abrasives and chemicals (Ken, brief update 13:00).
      ["coa", [
        /\bcertificates?\s+of\s+analysis\b/i,
        /\bC\.?O\.?A\.?s?\b/
      ]],
      ["reach", [
        /\bREACH\s+(?:compliant|compliance|statement|declaration|SVHC)\b/i,
        /\bREACH\b/
      ]],
      ["rohs", [
        /\bRoHS(?:\s*[23])?\b/i
      ]]
    ].freeze

    # Specialty metals by chemistry (research 3.2, DFARS): any stainless, nickel
    # alloy, or titanium. 304 and 316 are named there as specialty metals.
    SPECIALTY_WORDS = /\bstainless\b|\bSS\b|\bnickel\b|\binconel\b|\bmonel\b|\bhastelloy\b|\btitanium\b|\b(?:304|316)L?\b/i
    FUNDING_WORDS = /\bDOT\b|\bfederal(?:ly)?\b|\bFHWA\b|\bhighway\b|\btransit\b|\bwater\b|\bbridge\b/i
    BUYER_WORDS = /pressure[\s-]+vessel|boiler/i
    MARKING_WORDS = /\bITAR\b|\bexport[\s-]+control/i

    # text:    the RFQ line (and optionally surrounding RFQ text)
    # spec:    parser output, string keys: "material", "grade", "form", "standard", "finish"
    # context: symbol keys: :ship_to_defense, :dpas_rating, :attachment_markings, :funding, :buyer_type
    # Returns an Array of Hashes with string keys ("requirement", "label", "evidence",
    # "trigger", "note"), stated flags first (in line order), then implied, then context.
    # One flag per requirement: a stated trigger wins over implied, implied over context,
    # and the weaker triggers are mentioned in the note.
    def self.flags(text:, spec: {}, context: {})
      text = text.to_s
      spec = spec.is_a?(Hash) ? spec : {}
      context = context.is_a?(Hash) ? context : {}

      candidates = stated_candidates(text, spec) + implied_candidates(spec) + context_candidates(text, spec, context)
      merged = merge(candidates)
      add_cross_notes(merged)
      sort(merged).map { |candidate| to_flag(candidate) }
    end

    def self.stated_candidates(text, spec)
      found = STATED.filter_map do |requirement, patterns|
        match = patterns.lazy.filter_map { |pattern| pattern.match(text) }.first
        next unless match

        candidate(requirement, "stated", match[0], stated_note(requirement, match[0], text, spec), match.begin(0))
      end

      # "EN 10204" with no type written: the research says 3.1 is the usual request,
      # but which type is a question for the buyer, not a guess.
      unless found.any? { |c| c[:requirement].start_with?("en10204_") }
        match = EN_10204.match(text)
        if match
          note = "The line names EN 10204 without a certificate type; 3.1 (lot-specific results, independent inspector) is the usual request, but ask whether 3.1 or 3.2 (third-party witnessed) is needed. Research confidence: medium-high on the four types."
          found << candidate("en10204_3_1", "stated", match[0], note, match.begin(0))
        end
      end
      found
    end

    def self.implied_candidates(spec)
      standard = fetch(spec, "standard").to_s.strip
      return [] if standard.empty?

      if standard.match?(/\bSA[\s-]?\d{3}/i)
        [
          candidate("asme_sa", "implied", standard,
                    "#{standard} is an ASME SA spec: the S prefix means ASME adopted the ASTM spec for Boiler and Pressure Vessel Code use, and some grades carry extra ASME requirements. Ask whether the cert must show the SA designation and whether a code stamp is needed. Research confidence: medium-high as a trigger (Wermac, medium, on the SA vs A detail)."),
          candidate("mtr", "implied", standard,
                    "#{standard} is code material, which the research lists among the spec families where a mill test report is expected; confirm the buyer wants it with the shipment. Research confidence: high for the MTR trigger.")
        ]
      elsif standard.match?(/\bA[\s-]?500\b/i)
        [candidate("mtr", "implied", standard,
                   "A500 structural tube ships with a mill test report per bundle (Atlas Tube), so this flag is informational and needs no question to the buyer. Research confidence: high for the trigger; whether heat traceability survives cutting was not researched.")]
      elsif standard.match?(/\bA[\s-]?312\b/i)
        [candidate("mtr", "implied", standard,
                   "A312 stainless pipe is a pressure grade, which the research lists among the spec families where a mill test report is expected; confirm the buyer wants it with the shipment. Research confidence: high for the MTR trigger, but the A312 scope itself was not verified in the research.")]
      elsif standard.match?(/\bA[\s-]?479\b/i)
        [candidate("mtr", "implied", standard,
                   "A479 is the boiler and pressure vessel bar spec (A276 is general use), so the choice signals code use and a mill test report is expected; confirm with the buyer. Research confidence: high for the MTR trigger, medium-low on the A479 reading (vendor pages).")]
      elsif standard.match?(/\bAMS\b/i)
        ams = "AMS specs are aerospace and were not researched (paid SAE standards); the research says to treat an AMS number as a trigger to ask for certs and origin until someone with access checks. Research confidence: low."
        [candidate("mtr", "implied", standard, ams), candidate("origin", "implied", standard, ams)]
      else
        []
      end
    end

    def self.context_candidates(text, spec, context)
      found = []

      ship = [true, "true", "yes"].include?(fetch(context, :ship_to_defense))
      dpas = fetch(context, :dpas_rating).to_s.strip
      metal = specialty_metal_evidence(text, spec)
      if (ship || !dpas.empty?) && metal
        parts = []
        parts << "defense ship-to" if ship
        parts << "DPAS #{dpas}" unless dpas.empty?
        note = "No DFARS wording is in the line, but the material (#{metal}) is a specialty metal by chemistry and the #{parts.join(' and ')} suggest the DFARS 252.225-7009 flow-down applies; ask whether the PO includes the clause or a melt-origin requirement. Medium confidence: this is an inference from context, and the research rates the DFARS triggers medium-high."
        note += " A DPAS rating also requires written acceptance or rejection within 15 working days for DO and 10 days for DX, and must pass to suppliers (15 CFR 700.13)." unless dpas.empty?
        found << candidate("dfars", "context", parts.join(", "), note)
      end

      marking = Array(fetch(context, :attachment_markings)).map(&:to_s).find { |m| m.match?(MARKING_WORDS) }
      if marking
        found << candidate("itar", "context", "attachment marked \"#{marking}\"",
                           "The attachment carries an export-control marking; raw metal is rarely ITAR itself, the controlled item is usually the drawing or technical data, so flag it, do not interpret it: keep the files inside the quoting team and ask the buyer to confirm handling rules before the drawing circulates. Research confidence: low (no public source found on whether mill-form metal is USML-controlled).")
      end

      funding = fetch(context, :funding).to_s.strip
      if funding.match?(FUNDING_WORDS)
        found << candidate("buy_america", "context", "funding: #{funding}",
                           "Nothing in the line says Buy America, but the funding (#{funding}) matches the research's outside-the-line triggers (federal or state-DOT-funded projects, water or transit grants); ask whether Buy America (23 CFR 635.410) or BABA applies and what certification wording the agency requires. Research confidence: medium-high, from agency summaries.")
      end

      buyer = fetch(context, :buyer_type).to_s.strip
      if buyer.match?(BUYER_WORDS)
        found << candidate("asme_sa", "context", "buyer: #{buyer}",
                           "Nothing in the line says ASME, but a #{buyer} buyer is the research's outside-the-line trigger for code material; ask whether the material must be supplied to the SA spec and whether a code stamp is needed. Research confidence: medium-high.")
      end

      found
    end

    def self.stated_note(requirement, evidence, text, spec)
      case requirement
      when "mtr"
        if evidence.match?(/\A3\.1\z/)
          "A 3.1 certificate is itself a mill test certificate with results from the delivered lot, so one document can satisfy both flags; check that the stock's heat number is still traceable on cut pieces. Research confidence: high for the MTR trigger."
        else
          "An MTR reports one heat's chemistry and mechanical tests; whether the buyer gets one is set by the order, not by the metal, so check that the stock's heat number is still traceable on cut pieces. Research confidence: high."
        end
      when "en10204_3_1"
        note = "A 3.1 certificate reports test results from the delivered lot, signed by an inspector independent of production; confirm against the buyer's spec, since one research source contradicts itself on who issues it. Research confidence: medium-high."
        note += " A bare \"3.1\" could also be a number, so confirm it means the certificate type." if evidence.match?(/\A3\.1\z/)
        note
      when "en10204_3_2"
        note = "A 3.2 certificate adds validation by the buyer's representative or a third-party inspector, which can add scheduling, so the research says it needs a human, not an auto-quote. Research confidence: medium-high."
        note += " A bare \"3.2\" could also be a number, so confirm it means the certificate type." if evidence.match?(/\A3\.2\z/)
        note
      when "dfars"
        note = "DFARS 252.225-7009 requires specialty metals (any stainless, nickel alloy, or titanium) in delivered items to be melted or produced in the US, its outlying areas, or a qualifying country; ask whether a qualifying-country melt is acceptable and whether the stock's cert shows melt country. Research confidence: high on the clause text, medium-high as a trigger."
        note += " This line's material was not identified as a specialty metal, so ask whether the clause applies to it (the research says ordinary A36 is generally not one; chemistry check needed)." unless specialty_metal_evidence(text, spec)
        note
      when "buy_america"
        note = "Buy America (23 CFR 635.410) requires every manufacturing step on steel, including coating such as galvanizing, to occur in the US, and the mill test report must state where the steel was melted and manufactured; ask which agency wording is required. Research confidence: medium-high, from agency summaries."
        note += " A bare \"domestic\" does not say whether the buyer means Buy America, DFARS, or melt origin; the research calls this a clarifying question, not a guess." if evidence.match?(/\Adomestic\z/i)
        note += " The research covers Buy America and BABA, not the Buy American Act, so confirm which rule the buyer means." if evidence.match?(/American\z/i)
        note
      when "origin"
        "Melt location (the furnace) and rolling or finishing location are two different questions that RFQs blend; ask which the buyer needs and check whether the stock's cert shows melt country. Research confidence: medium."
      when "itar"
        "Raw metal is rarely ITAR itself; the controlled item is usually the drawing or technical data, so do not forward the files outside the quoting team and ask the buyer about handling (US persons only, domestic suppliers only). Research confidence: low; flag, do not interpret."
      when "pmi"
        "PMI checks the metal's actual chemistry with a handheld analyzer rather than the paperwork (API RP 578, ASTM E1476); ask whether RudCo performs it, supplies a report, or the buyer checks on receipt. Research confidence: medium (vendor pages; API 578 not read)."
      when "nace"
        "NACE MR0175 / ISO 15156 sour service: for carbon and low-alloy steel the usual limit is 22 HRC maximum hardness, and the standard does not itself require a certificate statement, so ask what the MTR must show (hardness values, heat-treat condition, HIC results). Research confidence: medium."
      when "coa"
        "A certificate of analysis reports the measured properties of the delivered lot (for abrasives: size distribution, hardness, chemistry); RudCo lists COAs among the paperwork it supplies, so confirm which lot-level values the buyer needs on it. Source: RudCo profile, not the domain research."
      when "reach"
        "REACH is the EU chemicals regulation; the buyer wants a statement on substances of very high concern in the product; RudCo lists REACH paperwork, so confirm the statement format the buyer accepts. Source: RudCo profile; a lowercase \"reach\" is the verb and is not matched."
      when "rohs"
        "RoHS restricts hazardous substances (lead, cadmium, mercury, hexavalent chromium and others) in products; cadmium-plated hardware is a known RoHS exception question, so confirm whether a declaration or an exemption applies. Source: RudCo profile."
      when "asme_sa"
        "The SA prefix means ASME adopted the ASTM spec for Boiler and Pressure Vessel Code use, some grades carry extra ASME requirements, and many mills dual-mark; ask whether the cert must show the SA designation and whether a code stamp or PMI is needed. Research confidence: medium-high as a trigger (Wermac, medium, on the SA vs A detail)."
      end
    end

    # The value that identifies a specialty metal (spec material or grade first, then the text), or nil.
    def self.specialty_metal_evidence(text, spec)
      material = fetch(spec, "material").to_s
      return material if material.match?(SPECIALTY_WORDS)

      grade = fetch(spec, "grade").to_s
      return grade if grade.match?(SPECIALTY_WORDS)

      match = SPECIALTY_WORDS.match(text)
      match && match[0]
    end

    def self.merge(candidates)
      candidates.group_by { |c| c[:requirement] }.map do |_requirement, group|
        best, *rest = group.sort_by { |c| TRIGGER_RANK.fetch(c[:trigger]) }
        rest.each do |other|
          next if other[:evidence].casecmp?(best[:evidence])

          best = best.merge(note: "#{best[:note]} #{also_sentence(other)}")
        end
        best
      end
    end

    def self.also_sentence(candidate)
      case candidate[:trigger]
      when "implied" then "The spec standard #{candidate[:evidence]} also implies it."
      else "Context also points at it (#{candidate[:evidence]})."
      end
    end

    # Melt wording with no DFARS flag: the research lists it as a DFARS trigger too, so say so.
    def self.add_cross_notes(flags)
      return if flags.any? { |c| c[:requirement] == "dfars" }

      origin = flags.find { |c| c[:requirement] == "origin" && c[:trigger] == "stated" && c[:evidence].match?(/\bmelt/i) }
      return unless origin

      origin[:note] = "#{origin[:note]} The research also lists melt wording as a DFARS trigger; ask whether DFARS 252.225-7009 or Buy America is behind it."
    end

    # Stated flags in line order, then implied, then context. An MTR flag read from a
    # bare "3.1" follows the EN 10204 flag it derives from.
    def self.sort(flags)
      flags.sort_by do |c|
        derived = c[:requirement] == "mtr" && c[:evidence].match?(/\A3\.1\z/) ? 1 : 0
        [TRIGGER_RANK.fetch(c[:trigger]), c[:position] || 0, derived, ORDER.index(c[:requirement])]
      end
    end

    def self.candidate(requirement, trigger, evidence, note, position = nil)
      { requirement: requirement, trigger: trigger, evidence: evidence, note: note, position: position }
    end

    def self.to_flag(candidate)
      {
        "requirement" => candidate[:requirement],
        "label" => LABELS.fetch(candidate[:requirement]),
        "evidence" => candidate[:evidence],
        "trigger" => candidate[:trigger],
        "note" => candidate[:note]
      }
    end

    # Tolerates string or symbol keys; the interface says string keys for spec and symbol keys for context.
    def self.fetch(hash, key)
      return nil unless hash.is_a?(Hash)

      hash.fetch(key.to_s) { hash[key.to_sym] }
    end
  end
end
