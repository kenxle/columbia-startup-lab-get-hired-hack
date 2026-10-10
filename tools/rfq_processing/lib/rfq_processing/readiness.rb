# frozen_string_literal: true

module RfqProcessing
  # The deterministic rule for a line's state. A confidence score never turns a
  # missing field into Ready. Every held line gets one question, with choices
  # when the catalog or the tables can name them.
  module Readiness
    Decision = Struct.new(:state, :question, :unresolved_fields, :choices, keyword_init: true)

    # match: the matcher's answer (Hash with string keys: "status", "best", "candidates"), or nil.
    def self.decide(reading, match: nil, position: 1)
      unresolved = (reading.unknowns.map { |u| u["field"] } + reading.conflicts.flat_map { |c| c["fields"] }).uniq
      unresolved -= ["form"] if reading.fields["part_number"] # hardware needs no metals form

      if reading.conflicts.any? || unresolved.any?
        choices = choices_for(reading)
        if match && match["status"] == "ambiguous"
          Array(match["candidates"]).each do |c|
            choices << { "label" => "#{c['part_number'] || c['item_id']}: #{c['description'] || c['reason']}"[0, 120], "value" => c["item_id"] }
          end
        end
        question = question_for(reading, position)
        if match && match["status"] == "ambiguous" && match["total_candidates"].to_i > 0
          names = Array(match["candidates"]).map { |c| c["part_number"] || c["item_id"] }
          question = "#{question} #{match['total_candidates']} catalog items fit so far, for example #{names.join(', ')}."[0, 990]
        end
        Decision.new(state: "needs_buyer", question: question, unresolved_fields: unresolved, choices: choices)
      elsif match.nil? || match["status"] == "no_match"
        Decision.new(state: "no_match", question: no_match_question(reading, position), unresolved_fields: [], choices: [])
      elsif match["status"] == "ambiguous"
        cands = Array(match["candidates"])
        Decision.new(state: "needs_buyer", question: ambiguous_question(reading, cands, position),
                     unresolved_fields: reading.fields["part_number"] ? [] : ["catalog item"],
                     choices: cands.map { |c| { "label" => "#{c['part_number'] || c['item_id']}: #{c['reason']}", "value" => c["item_id"] } })
      else
        Decision.new(state: "ready", question: nil, unresolved_fields: [], choices: [])
      end
    end

    def self.question_for(reading, position)
      parts = reading.conflicts.map { |c| c["message"] }
      missing = reading.unknowns.map { |u| u["field"] } - reading.conflicts.flat_map { |c| c["fields"] }
      if missing.any?
        names = missing.map { |f| field_name(f) }
        parts << "Please give the #{names.join(', ')}."
      end
      text = "Line #{position}: #{parts.join(' ')}"
      text[0, 990]
    end

    def self.no_match_question(reading, position)
      "No match in the current catalog for line #{position} (#{describe(reading)}). Should we quote it from an outside source at a stated lead time, or remove this line?"[0, 990]
    end

    def self.ambiguous_question(reading, candidates, position)
      names = candidates.map { |c| c["part_number"] || c["item_id"] }
      "Line #{position} (#{describe(reading)}) fits #{candidates.size} catalog items: #{names.join(', ')}. Which one do you mean?"[0, 990]
    end

    def self.choices_for(reading)
      choices = []
      reading.conflicts.each do |c|
        case c["code"]
        when "material_missing_with_gauge"
          gauge = reading.fields["gauge"]
          GaugeTable.candidates(gauge: gauge, form: reading.fields["form"]).each do |cand|
            choices << { "label" => "#{cand[:table]}, #{gauge} ga = #{cand[:thickness_in]} in", "value" => cand[:table] }
          end
        when "decimal_near_gauge", "gauge_vs_decimal", "gauge_table_gap"
          c["message"].scan(/(\d*\.\d+) in/).flatten.uniq.each do |v|
            choices << { "label" => "#{v} in", "value" => v }
          end
        when "spec_conflict"
          Array(reading.fields["standards"]).each { |s| choices << { "label" => s, "value" => s } }
        when "shape_vs_spec"
          [["Square tube, A500 structural", "A500"], ["Square tube, A513 mechanical", "A513"], ["Round pipe, A53", "A53"]].each do |label, value|
            choices << { "label" => label, "value" => value }
          end
        when "strength_mismatch"
          [["A572 Grade 50", "A572 Gr 50"], ["A36/A572-50 dual certified", "A36/A572-50"]].each { |l, v| choices << { "label" => l, "value" => v } }
        when "sheet_plate_boundary"
          [["Hot rolled plate", "plate"], ["Cold rolled sheet", "sheet"]].each { |l, v| choices << { "label" => l, "value" => v } }
        when "tube_spec_missing"
          [["A500 structural", "A500"], ["A513 mechanical", "A513"]].each { |l, v| choices << { "label" => l, "value" => v } }
        when "coating_weight_missing"
          [["G60", "G60"], ["G90", "G90"]].each { |l, v| choices << { "label" => l, "value" => v } }
        end
      end
      choices.uniq
    end

    def self.describe(reading)
      f = reading.fields
      [f["material"], f["grade"], f["form"] || f["part_number"] || f["part_family"]].compact.join(" ")
    end

    FIELD_NAMES = {
      "thickness_in" => "thickness", "wall_in" => "wall thickness", "width_in" => "width", "length_in" => "length",
      "side_a_in" => "first side", "side_b_in" => "second side", "diameter_in" => "diameter", "nominal_size_in" => "nominal pipe size",
      "part_number" => "full part number", "quantity" => "quantity", "material" => "material", "form" => "product form",
      "schedule" => "pipe schedule", "standard" => "specification", "grade" => "grade"
    }.freeze

    def self.field_name(field)
      FIELD_NAMES.fetch(field, field.sub("_in", "").tr("_", " "))
    end
  end
end
