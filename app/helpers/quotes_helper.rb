module QuotesHelper
  SPEC_FIELDS = %w[material grade form thickness width length standard finish].freeze

  SPEC_LABELS = {
    "material" => "Material",
    "grade" => "Grade",
    "form" => "Form",
    "thickness" => "Thickness",
    "width" => "Width",
    "length" => "Length",
    "standard" => "Standard",
    "finish" => "Finish",
    "quantity" => "Quantity"
  }.freeze

  STATE_CLASSES = {
    "ready" => "status--ready",
    "needs_buyer" => "status--needs-buyer",
    "no_match" => "status--no-match"
  }.freeze

  # Placeholder for any value the RFQ or pipeline did not supply.
  def unknown_marker
    tag.span(class: "unknown") do
      safe_join([
        tag.span("–", aria: { hidden: true }),
        tag.span("Not stated", class: "visually-hidden")
      ])
    end
  end

  def display_value(value)
    text = value.is_a?(String) ? value.strip : value
    text.blank? ? unknown_marker : text.to_s
  end

  def display_money(amount)
    return unknown_marker if amount.nil?

    number_to_currency(amount, unit: "USD ", format: "%u%n", precision: amount == amount.round(2) ? 2 : 4)
  end

  def display_quantity(line)
    return unknown_marker if line.quantity.nil?

    number = number_with_precision(line.quantity, precision: 4, strip_insignificant_zeros: true, delimiter: ",")
    line.quantity_unit.present? ? "#{number} #{line.quantity_unit}" : number
  end

  def display_time(time)
    return unknown_marker if time.nil?

    tag.time(time.strftime("%b %-d, %Y, %H:%M"), datetime: time.iso8601)
  end

  def spec_label(key)
    SPEC_LABELS.fetch(key.to_s) { key.to_s.humanize }
  end

  def spec_value(line, key)
    spec = line.spec.is_a?(Hash) ? line.spec : {}
    spec[key.to_s] || spec[key.to_sym]
  end

  def evidence_for(line, key)
    evidence = line.evidence.is_a?(Hash) ? line.evidence : {}
    entry = evidence[key.to_s] || evidence[key.to_sym]
    return nil unless entry.is_a?(Hash)

    entry.transform_keys(&:to_s)
  end

  def unresolved_field?(line, key)
    Array(line.unresolved_fields).map(&:to_s).include?(key.to_s)
  end

  def edited_field?(line, key)
    Array(line.edited_fields).map(&:to_s).include?(key.to_s)
  end

  def status_badge(line)
    tag.span(line.status_label, class: ["status", STATE_CLASSES.fetch(line.state.to_s, "status--unknown")])
  end

  def quote_status_badge(quote)
    if quote.approved?
      tag.span("Approved", class: "status status--ready")
    elsif quote.awaiting_processing?
      tag.span("Awaiting processing", class: "status status--neutral")
    else
      tag.span("In review", class: "status status--needs-buyer")
    end
  end

  def sample_badge(label = "Sample data")
    tag.span(label, class: "sample-badge")
  end

  def price_editable?(line)
    line.state.to_s == "ready" && line.catalog_sku.present?
  end

  def catalog_match_stale?(line)
    (Array(line.edited_fields) & QuoteLine::REPROCESSING_FIELDS).any?
  end

  def held_line?(line)
    !line.quotable?
  end

  def benchmark_for(line)
    benchmark = line.benchmark.is_a?(Hash) ? line.benchmark : {}
    benchmark.transform_keys(&:to_s)
  end

  def sample_benchmark?(line)
    benchmark_for(line)["kind"].to_s == "sample"
  end

  def rep_entered_price?(line)
    line.rep_entered_price?
  end

  def compliance_entries(line)
    Array(line.compliance).filter_map do |entry|
      entry.transform_keys(&:to_s) if entry.is_a?(Hash)
    end
  end

  def selected_line?(line, selected_line)
    selected_line.present? && line.id == selected_line.id
  end

  # Escapes the original RFQ text and wraps any exact evidence phrase in <mark>.
  # Every fragment passes through safe_join, so source text is never trusted as HTML.
  def highlighted_source(text, phrases)
    return "" if text.blank?

    needles = Array(phrases).filter_map { |phrase| phrase.to_s.strip.presence }
                            .select { |phrase| phrase.length >= 2 }
                            .uniq
                            .sort_by { |phrase| -phrase.length }
    return text if needles.empty?

    pattern = Regexp.new("((?<![[:alnum:]_])(?:#{needles.map { |phrase| Regexp.escape(phrase) }.join('|')})(?![[:alnum:]_]))")
    fragments = text.split(pattern)
    safe_join(fragments.each_with_index.map do |fragment, index|
      index.odd? ? tag.mark(fragment, class: "evidence-mark") : fragment
    end)
  end

  def evidence_phrases(line)
    return [] if line.nil?

    phrases = Array(line.compliance).filter_map { |entry| entry["evidence"].presence if entry.is_a?(Hash) }
    return [line.original_text, *phrases] if line.original_text.present?
    evidence = line.evidence.is_a?(Hash) ? line.evidence : {}
    evidence.each_value do |entry|
      phrases << (entry["text"] || entry[:text]) if entry.is_a?(Hash)
    end
    phrases
  end

  def approval_blockers(quote, lines)
    blockers = []
    blockers << "No line is ready to quote yet." if quote.ready_count.to_i.zero?
    missing = lines.select { |line| held_line?(line) && line.clarification_question.blank? }
    if missing.any?
      positions = missing.map(&:position).to_sentence
      blockers << "Held line #{positions} #{missing.one? ? 'needs' : 'need'} a buyer question before approval."
    end
    blockers << "Some lines are not complete enough to approve." if blockers.empty?
    blockers
  end
end
