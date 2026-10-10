module CatalogMatchesHelper
  OUTCOME_LABELS = {
    "match" => [ "Match", "status--ready" ],
    "candidates" => [ "Needs the buyer", "status--needs-buyer" ],
    "no_match" => [ "No match", "status--no-match" ]
  }.freeze

  # The SVG is built from numbers and escaped labels only (CatalogMatch::Drawing).
  def item_drawing(item)
    return "" unless item

    CatalogMatch::Drawing.svg(item).html_safe # rubocop:disable Rails/OutputSafety
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
