module CatalogMatchesHelper
  OUTCOME_LABELS = {
    "match" => [ "Match", "status--ready" ],
    "candidates" => [ "Needs the buyer", "status--needs-buyer" ],
    "no_match" => [ "No match", "status--no-match" ]
  }.freeze

  # The catalog item's own spec fields, labeled, in the order a rep reads them.
  # Fields the item does not have are left out, never filled in.
  def item_specs(item)
    return [] unless item

    inches = ->(value) { value && "#{reading_value(value.to_f)} in" }
    thickness = if item["gauge"] then "#{item['gauge']} ga (#{item['thickness_in']} in)"
                elsif item["wall_in"] then "#{item['wall_in']} in wall"
                else inches.call(item["thickness_in"])
                end
    size = if item["width_in"] && item["length_in"] && %w[sheet plate].include?(item["form"])
             "#{reading_value(item['width_in'].to_f)} x #{reading_value(item['length_in'].to_f)} in"
           elsif item["size_a_in"]
             [ item["size_a_in"], item["size_b_in"] ].compact.map { |value| reading_value(value.to_f) }.join(" x ") + " in"
           elsif item["diameter_in"] then "#{reading_value(item['diameter_in'].to_f)} in dia"
           elsif item["nps"] then "#{reading_value(item['nps'].to_f)} in NPS, sch #{item['schedule']}"
           else item["size"]
           end
    length = item["length_in"] && !%w[sheet plate].include?(item["form"]) ? "#{reading_value(item['length_in'].to_f / 12)} ft" : nil
    length ||= item["nominal_length_display"] && "#{item['nominal_length_display']} in (grip #{item['grip_length_display']} in)"
    {
      "Material" => item["material"],
      "Grade" => [ item["grade"], item["temper"] ].compact.join("-").presence,
      "Form" => item["form_detail"] || item["form"],
      "Thickness" => thickness,
      "Size" => size,
      "Thread" => item["thread"],
      "Length" => length,
      "Finish" => item["finish"],
      "Standard" => item["standard"],
      "Sold by" => item["unit"]
    }.compact_blank.to_a
  end

  def match_outcome_badge(outcome)
    label, css = OUTCOME_LABELS.fetch(outcome, [ outcome.to_s.humanize, "status--unknown" ])
    tag.span(label, class: [ "status", css ])
  end

  def check_status_label(status)
    { "exact" => "Agrees", "near" => "Close, confirm", "conflict" => "Differs" }.fetch(status.to_s, status.to_s)
  end

  def reading_value(value)
    case value
    when true then "yes"
    when false then "no"
    when Float then value == value.round ? value.round.to_s : value.round(4).to_s
    else value.to_s
    end
  end
end
