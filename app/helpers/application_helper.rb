module ApplicationHelper
  def workspace_document_title(page_title: nil, quote: nil)
    unless quote&.persisted?
      return [page_title.presence, "Quote Desk"].compact.uniq.join(" · ")
    end

    lines = quote.quote_lines.to_a
    buyer_count = lines.count { |line| line.state == "needs_buyer" }
    no_match_count = lines.count { |line| line.state == "no_match" }
    attention = if quote.sent?
      "Sent"
    elsif buyer_count.positive?
      "#{pluralize(buyer_count, 'line')} #{buyer_count == 1 ? 'needs' : 'need'} the buyer"
    elsif no_match_count.positive?
      "#{pluralize(no_match_count, 'line')} #{no_match_count == 1 ? 'has' : 'have'} no match"
    elsif lines.empty?
      "Awaiting processing"
    elsif quote.approved?
      "Approved"
    else
      "Review required"
    end

    [attention, quote.reference, "Quote Desk"].join(" · ")
  end

  def quote_deadline_badge(quote, now: Time.current)
    due_at = quote.due_at
    if quote.sent?
      minutes = [(quote.sent_at - quote.created_at).div(60), 0].max
      label = "Sent in #{deadline_duration(minutes)}"
      state = "sent"
    else
      remaining = due_at - now
      if remaining <= 0
        label = "Overdue by #{deadline_duration((-remaining).div(60))}"
        state = "overdue"
      else
        label = "Due in #{deadline_duration((remaining / 60).ceil)}"
        state = remaining <= 3.hours ? "soon" : "calm"
      end
    end

    tag.span(label, class: "deadline deadline--#{state}",
      title: "Quote due #{due_at.strftime('%b %-d, %Y, %H:%M %Z')}",
      data: { quote_deadline: quote.sent? ? "sent" : "due", deadline_at: due_at.iso8601,
        received_at: quote.created_at.iso8601, sent_at: quote.sent? ? quote.sent_at.iso8601 : nil })
  end

  def deadline_duration(minutes)
    format("%dh %02dm", minutes / 60, minutes % 60)
  end

  def local_email_preview_available?
    (Rails.env.development? && ActionMailer::Base.delivery_method == :letter_opener) ||
      (Rails.env.test? && ActionMailer::Base.delivery_method == :test)
  end
end
