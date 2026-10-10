class QuoteLine < ApplicationRecord
  STATES = %w[ready needs_buyer no_match].freeze
  HELD_STATES = %w[needs_buyer no_match].freeze
  STATE_LABELS = {
    "ready" => "Ready",
    "needs_buyer" => "Question to send",
    "no_match" => "No match"
  }.freeze
  SPEC_KEYS = %w[material grade form thickness width length standard finish part_number diameter thread grip drilling].freeze
  EVIDENCE_KEYS = (SPEC_KEYS + %w[quantity]).freeze
  EVIDENCE_ENTRY_KEYS = %w[text location explanation].freeze
  COMPLIANCE_ENTRY_KEYS = %w[label evidence note].freeze
  BENCHMARK_KEYS = %w[name as_of unit kind explanation].freeze
  EDITABLE_ATTRIBUTES = %w[description quantity quantity_unit unit_price notes clarification_question].freeze
  REPROCESSING_FIELDS = (SPEC_KEYS + %w[quantity quantity_unit]).freeze
  REP_ENTERED_PRICE_SOURCE = "Rep-entered price".freeze
  MAXIMUM_DECIMAL = BigDecimal("1000000000")
  MAXIMUM_SPEC_VALUE_LENGTH = 200

  belongs_to :quote, inverse_of: :quote_lines
  has_many :buyer_question_deliveries, dependent: :nullify

  attribute :spec, default: -> { {} }
  attribute :evidence, default: -> { {} }
  attribute :compliance, default: -> { [] }
  attribute :unresolved_fields, default: -> { [] }
  attribute :edited_fields, default: -> { [] }

  before_validation :normalize_structured_fields

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :position, uniqueness: { scope: :quote_id }
  validates :line_id, uniqueness: { scope: :quote_id }, allow_nil: true
  validates :state, inclusion: { in: STATES }
  validates :quantity, numericality: { greater_than: 0, less_than: MAXIMUM_DECIMAL }, allow_nil: true
  validates :unit_price, numericality: { greater_than_or_equal_to: 0, less_than: MAXIMUM_DECIMAL }, allow_nil: true
  validates :description, length: { maximum: 500 }
  validates :original_text, length: { maximum: 5_000 }
  validates :quantity_unit, length: { maximum: 40 }
  validates :catalog_sku, length: { maximum: 100 }
  validates :price_source, length: { maximum: 200 }
  validates :clarification_question, length: { maximum: 1_000 }
  validates :notes, length: { maximum: 2_000 }
  validate :ready_line_is_complete
  validate :no_match_line_has_no_catalog_item
  validate :spec_shape
  validate :evidence_shape
  validate :compliance_shape
  validate :benchmark_shape
  validate :field_lists_shape
  validate :processing_metadata_shape
  validate :lead_time_shape

  def spec_value(spec_key)
    spec.is_a?(Hash) ? spec[spec_key.to_s] : nil
  end

  # A line counts toward the quote only when every pricing input is present
  # and nothing is left unresolved. The stored state alone is not trusted.
  def quotable?
    state == "ready" &&
      quantity.present? && quantity.positive? &&
      !unit_price.nil? && !unit_price.negative? &&
      price_source.present? &&
      catalog_sku.present? &&
      Array(unresolved_fields).empty?
  end

  def held?
    !quotable?
  end

  def line_total
    return nil unless quotable?

    (quantity * unit_price).round(2)
  end

  def status_label
    return "Waiting on buyer" if state == "needs_buyer" && current_question_delivery

    STATE_LABELS.fetch(state, "Unknown")
  end

  def question_preview_eligible?
    HELD_STATES.include?(state) && clarification_question.present?
  end

  def question_delivery_fingerprint
    content = {
      question: clarification_question, state: state, spec: spec, quantity: quantity&.to_s("F"),
      quantity_unit: quantity_unit, description: description, original_text: original_text,
      unresolved_fields: unresolved_fields, choices: processing&.dig("question_choices")
    }
    canonical = lambda do |value|
      case value
      when Hash then value.stringify_keys.sort.to_h.transform_values { |entry| canonical.call(entry) }
      when Array then value.map { |entry| canonical.call(entry) }
      else value
      end
    end
    Digest::SHA256.hexdigest(JSON.generate(canonical.call(content)))
  end

  def current_question_delivery
    return unless persisted? && question_preview_eligible?

    buyer_question_deliveries.previewed.where(fingerprint: question_delivery_fingerprint).order(previewed_at: :desc, id: :desc).first
  end

  # Called only by explicit drafting actions. Seed data and ordinary saves never
  # dispatch mail artifacts. Capture this draft and wait for its transaction.
  def enqueue_question_preview_after_commit
    return unless Rails.env.development? || Rails.env.test?
    return unless persisted? && question_preview_eligible?

    line_id = id
    fingerprint = question_delivery_fingerprint
    ActiveRecord.after_all_transactions_commit do
      begin
        current = QuoteLine.find_by(id: line_id)
        next unless current&.question_preview_eligible? && current.question_delivery_fingerprint == fingerprint
        next if current.buyer_question_deliveries.exists?(fingerprint: fingerprint, channel: "local_preview")

        DispatchBuyerQuestionJob.perform_later(line_id, fingerprint)
      rescue StandardError
        # A local preview failure must not interrupt the saved RFQ work.
        nil
      end
    end
  end

  def display_description
    description.presence || original_text.to_s.squish.truncate(80).presence || "Line #{position}"
  end

  def sourced_lead_time?
    quotable? && lead_time.present? && lead_time_source.present?
  end

  def display_lead_time
    sourced_lead_time? ? lead_time : "to confirm"
  end

  def rep_entered_price?
    price_source == REP_ENTERED_PRICE_SOURCE
  end

  def sample_benchmark?
    benchmark.is_a?(Hash) && benchmark["kind"] == "sample"
  end

  # Applies a quoting rep's edit. Spec or quantity changes send the line back
  # for reprocessing as Question to send; price and note changes keep the state.
  # Any saved change clears the quote approval in the same transaction.
  def apply_manual_edit(edit_attributes)
    quote.with_lock do
      reload if persisted?
      edit_attributes = edit_attributes.to_h.stringify_keys
      changed_fields = assign_editable_attributes(edit_attributes)
      changed_fields.concat(assign_spec_edits(edit_attributes["spec"])) if edit_attributes.key?("spec")
      next true if changed_fields.empty?

      reprocessing_fields = changed_fields & REPROCESSING_FIELDS
      if reprocessing_fields.any?
        self.state = "needs_buyer"
        self.lead_time = nil
        self.lead_time_source = nil
        if clarification_question.blank?
          field_names = reprocessing_fields.map { |field_name| field_name.humanize(capitalize: false) }.join(", ")
          self.clarification_question =
            "Line #{position} was edited by the quoting rep (#{field_names}). Please confirm these details before this line is priced."
        end
      end

      if changed_fields.include?("unit_price")
        self.price_source = unit_price.nil? ? nil : REP_ENTERED_PRICE_SOURCE
      end

      self.edited_fields = Array(edited_fields) | changed_fields

      if save
        quote.invalidate_approval!
        enqueue_question_preview_after_commit if saved_change_to_clarification_question?
        true
      else
        false
      end
    end
  end

  private

  def lead_time_shape
    %w[lead_time lead_time_source].each do |field|
      value = read_attribute_before_type_cast(field)
      unless value.nil? || (value.is_a?(String) && value.length <= 200)
        errors.add(field, "must be text of 200 characters or fewer")
      end
    end
    if lead_time.present? && lead_time_source.blank?
      errors.add(:lead_time_source, "is required when a lead time is provided")
    end
  end

  def processing_metadata_shape
    identifier = line_id_before_type_cast
    unless identifier.nil? || Quote.valid_processing_identifier?(identifier)
      errors.add(:line_id, "must be nonblank text of 200 characters or fewer")
    end
    unless Quote.valid_processing_metadata?(processing)
      errors.add(:processing, "must be bounded JSON")
    end
  end

  def assign_editable_attributes(edit_attributes)
    changed_fields = []
    EDITABLE_ATTRIBUTES.each do |attribute_name|
      next unless edit_attributes.key?(attribute_name)

      value = edit_attributes[attribute_name].to_s.strip
      self[attribute_name] = value.empty? ? nil : value
      changed_fields << attribute_name if will_save_change_to_attribute?(attribute_name)
    end
    changed_fields
  end

  def assign_spec_edits(submitted_spec)
    return [] unless submitted_spec.respond_to?(:to_h)

    current_spec = spec.is_a?(Hash) ? spec : {}
    new_spec = current_spec.dup
    changed_fields = []
    submitted_spec.to_h.stringify_keys.slice(*SPEC_KEYS).each do |spec_key, value|
      cleaned = value.to_s.strip
      if cleaned.empty?
        new_spec.delete(spec_key)
      else
        new_spec[spec_key] = cleaned
      end
      changed_fields << spec_key if new_spec[spec_key] != current_spec[spec_key]
    end
    self.spec = new_spec
    changed_fields
  end

  def normalize_structured_fields
    self.spec = {} if spec.nil?
    self.spec = spec.deep_stringify_keys if spec.is_a?(Hash)
    self.evidence = {} if evidence.nil?
    self.evidence = evidence.deep_stringify_keys if evidence.is_a?(Hash)
    self.benchmark = benchmark.deep_stringify_keys if benchmark.is_a?(Hash)
    self.compliance = [] if compliance.nil?
    if compliance.is_a?(Array)
      self.compliance = compliance.map { |entry| entry.is_a?(Hash) ? entry.deep_stringify_keys : entry }
    end
    self.unresolved_fields = [] if unresolved_fields.nil?
    self.edited_fields = [] if edited_fields.nil?
  end

  def ready_line_is_complete
    return unless state == "ready"

    errors.add(:quantity, "is required for a Ready line") if quantity.nil?
    errors.add(:unit_price, "is required for a Ready line") if unit_price.nil?
    errors.add(:price_source, "is required for a Ready line") if price_source.blank?
    errors.add(:catalog_sku, "is required for a Ready line") if catalog_sku.blank?
    errors.add(:unresolved_fields, "must be empty for a Ready line") if Array(unresolved_fields).any?
  end

  def no_match_line_has_no_catalog_item
    return unless state == "no_match" && catalog_sku.present?

    errors.add(:catalog_sku, "must be empty for a No match line")
  end

  def spec_shape
    unless spec.is_a?(Hash)
      errors.add(:spec, "must be a set of named fields")
      return
    end

    unknown_keys = spec.keys - SPEC_KEYS
    errors.add(:spec, "has unknown fields: #{unknown_keys.join(', ')}") if unknown_keys.any?
    spec.each do |spec_key, value|
      unless value.is_a?(String) && value.length <= MAXIMUM_SPEC_VALUE_LENGTH
        errors.add(:spec, "#{spec_key} must be text of #{MAXIMUM_SPEC_VALUE_LENGTH} characters or fewer")
      end
    end
  end

  def evidence_shape
    unless evidence.is_a?(Hash)
      errors.add(:evidence, "must be a set of named fields")
      return
    end

    unknown_keys = evidence.keys - EVIDENCE_KEYS
    errors.add(:evidence, "has unknown fields: #{unknown_keys.join(', ')}") if unknown_keys.any?
    evidence.each do |evidence_key, entry|
      unless entry.is_a?(Hash) && entry["text"].is_a?(String) && entry["text"].strip.present?
        errors.add(:evidence, "#{evidence_key} must quote the source text")
      end
    end
  end

  def compliance_shape
    unless compliance.is_a?(Array)
      errors.add(:compliance, "must be a list")
      return
    end

    compliance.each_with_index do |entry, index|
      unless entry.is_a?(Hash) && entry["label"].is_a?(String) && entry["label"].strip.present?
        errors.add(:compliance, "entry #{index + 1} needs a label")
      end
    end
  end

  def benchmark_shape
    return if benchmark.nil? || benchmark.is_a?(Hash)

    errors.add(:benchmark, "must be a set of named fields")
  end

  def field_lists_shape
    { unresolved_fields: unresolved_fields, edited_fields: edited_fields }.each do |attribute_name, value|
      next if value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) }

      errors.add(attribute_name, "must be a list of field names")
    end
  end
end
