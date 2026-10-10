module ApplicationHelper
  def workspace_document_title(page_title: nil, quote: nil)
    unless quote&.persisted?
      return [page_title.presence, "Quote Desk"].compact.uniq.join(" · ")
    end

    lines = quote.quote_lines.to_a
    buyer_count = lines.count { |line| line.state == "needs_buyer" }
    no_match_count = lines.count { |line| line.state == "no_match" }
    attention = if buyer_count.positive?
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

  def local_email_preview_available?
    (Rails.env.development? && ActionMailer::Base.delivery_method == :letter_opener) ||
      (Rails.env.test? && ActionMailer::Base.delivery_method == :test)
  end
end
