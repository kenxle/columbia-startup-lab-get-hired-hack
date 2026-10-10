class QuoteLinesController < ApplicationController
  include QuoteWorkspace::SessionScope

  SPEC_PARAMETER_KEYS = QuoteLine::SPEC_KEYS.map(&:to_sym).freeze
  EDITABLE_PARAMETER_KEYS = QuoteLine::EDITABLE_ATTRIBUTES.map(&:to_sym).freeze

  def update
    @quote = workspace_quotes.find(params[:quote_id])
    line = @quote.quote_lines.find(params[:id])
    @status = %w[all attention ready].include?(params[:status]) ? params[:status] : "all"
    @return_to = params[:return_to] == "buyer_questions" ? "buyer_questions" : nil

    saved = @quote.with_lock do
      version = params[:reviewed_version]
      unless version.is_a?(String) && version.present? && version == @quote.review_revision
        raise Quote::StaleReview
      end
      line.apply_manual_edit(line_edit_attributes)
    end

    if saved
      destination = if @return_to == "buyer_questions"
        quote_buyer_questions_path(@quote)
      else
        quote_path(@quote, line: line.id, status: (%w[all attention ready].include?(params[:status]) ? @status : nil))
      end
      redirect_to destination,
        notice: "Line #{line.position} saved. Approve the quote again before exporting."
    else
      @lines = @quote.quote_lines.reload.to_a
      @visible_lines = case @status
      when "attention" then @lines.reject(&:quotable?)
      when "ready" then @lines.select(&:quotable?)
      else @lines
      end
      @selected_line = line
      render "quotes/show", status: 422
    end
  rescue Quote::StaleReview
    redirect_to quote_path(@quote, line: line.id, status: @status),
      alert: "This quote changed. Your changes were not saved. Review the latest line and try again."
  end

  private

  # Accepts spec fields nested as quote_line[spec][material] or flat as
  # quote_line[material]. Catalog SKU, state and price source are not editable.
  def line_edit_attributes
    permitted = params.expect(quote_line: [ *EDITABLE_PARAMETER_KEYS, *SPEC_PARAMETER_KEYS, { spec: SPEC_PARAMETER_KEYS } ])
    submitted = permitted.to_h.stringify_keys

    attributes = submitted.slice(*QuoteLine::EDITABLE_ATTRIBUTES)
    nested_spec = submitted["spec"].respond_to?(:to_h) ? submitted["spec"].to_h.stringify_keys : {}
    flat_spec = submitted.slice(*QuoteLine::SPEC_KEYS)
    spec_edits = nested_spec.merge(flat_spec)
    attributes["spec"] = spec_edits if spec_edits.any?
    attributes
  end
end
