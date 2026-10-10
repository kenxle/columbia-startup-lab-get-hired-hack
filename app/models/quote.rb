class Quote < ApplicationRecord
  MAXIMUM_SOURCE_BYTES = 10.megabytes
  MAXIMUM_SOURCE_TEXT_LENGTH = 50_000
  ALLOWED_UPLOAD_EXTENSIONS = %w[.pdf .xlsx .xls .csv .txt .eml].freeze

  class NotApprovable < StandardError; end
  class StaleReview < NotApprovable; end
  class InvalidProcessingEvidence < ArgumentError
    attr_reader :problems

    def initialize(problems)
      @problems = problems
      super(problems.join("; "))
    end
  end

  PROCESSING_SOURCE_TYPES = %w[email pdf spreadsheet text csv].freeze
  PROCESSING_SOURCE_KEYS = %w[type filename pages rows].freeze

  has_many :quote_lines, -> { order(:position) }, dependent: :delete_all, inverse_of: :quote
  has_many :processing_runs, dependent: :delete_all
  has_many :buyer_question_deliveries, dependent: :delete_all

  scope :for_workspace, ->(workspace_token) { where(workspace_token: workspace_token.to_s) }

  validates :workspace_token, presence: true
  validates :title, presence: true, length: { maximum: 200 }
  validates :buyer_name, length: { maximum: 200 }
  validates :source_text, length: { maximum: MAXIMUM_SOURCE_TEXT_LENGTH }
  validates :original_filename, length: { maximum: 255 }
  validate :source_present
  validate :source_bytes_within_limit
  validate :original_filename_present_with_file
  validate :processing_revision_shape
  validate :processing_evidence_shape
  validate :sent_metadata_shape

  # Flat, bounded extraction metadata only. Unknown keys and source types are
  # rejected rather than silently retaining provider data or inventing a type.
  def self.processing_evidence_errors(source:, warnings:)
    problems = []
    unless source.nil?
      if !source.is_a?(Hash)
        problems << "source must be a hash or null"
      elsif source.keys.any? { |key| !key.is_a?(String) && !key.is_a?(Symbol) } ||
          source.keys.map(&:to_s).uniq.length != source.keys.length ||
          (source.keys.map(&:to_s) - PROCESSING_SOURCE_KEYS).any?
        problems << "source must contain only unique type, filename, pages and rows keys"
      else
        fields = source.stringify_keys
        problems << "source type is unsupported" unless PROCESSING_SOURCE_TYPES.include?(fields["type"])
        filename = fields["filename"]
        unless filename.nil? || (filename.is_a?(String) && filename.valid_encoding? && filename.length <= 255)
          problems << "source filename must be text of 255 characters or fewer, or null"
        end
        %w[pages rows].each do |key|
          value = fields[key]
          unless value.nil? || (value.is_a?(Integer) && value >= 0)
            problems << "source #{key} must be a nonnegative whole number or null"
          end
        end
      end
    end
    unless warnings.is_a?(Array) && warnings.length <= 100 && warnings.all? { |warning| warning.is_a?(String) && warning.valid_encoding? && warning.length <= 1_000 }
      problems << "warnings must be a list of at most 100 strings, each 1000 characters or fewer"
    end
    if problems.empty? && JSON.generate({ source: source, warnings: warnings }).bytesize > 32_768
      problems << "source and warnings must total 32 KiB or less"
    end
    problems
  rescue JSON::GeneratorError, EncodingError
    [ "source and warnings must be valid JSON text" ]
  end

  def self.normalized_processing_evidence(source:, warnings:)
    warnings = [] if warnings.nil?
    problems = processing_evidence_errors(source: source, warnings: warnings)
    raise InvalidProcessingEvidence.new(problems) if problems.any?

    { processing_source: source&.stringify_keys, processing_warnings: warnings.dup }
  end

  # Used for zero-line extraction failures as well as successful results.
  # Callers own their transaction, run status and explicit save.
  def assign_processing_evidence(source:, warnings:)
    assign_attributes(self.class.normalized_processing_evidence(source: source, warnings: warnings))
    self
  end

  # Optional provider metadata is inert JSON, bounded before serialization.
  # The depth and node limits also reject circular Ruby containers.
  def self.valid_processing_metadata?(value, revision: false)
    return true if value.nil?
    return false unless value.is_a?(Hash)

    remaining = 1_000
    inspect_value = lambda do |entry, depth|
      remaining -= 1
      return false if remaining.negative? || depth > 8

      case entry
      when Hash
        entry.size <= 1_000 && entry.keys.map(&:to_s).uniq.length == entry.size && entry.all? do |key, child|
          (key.is_a?(String) || key.is_a?(Symbol)) && key.to_s.bytesize <= 200 &&
            inspect_value.call(child, depth + 1)
        end
      when Array
        entry.size <= 1_000 && entry.all? { |child| inspect_value.call(child, depth + 1) }
      when String
        entry.valid_encoding? && entry.bytesize <= 32_768
      when Float
        entry.finite?
      when Integer, TrueClass, FalseClass, NilClass
        true
      else
        false
      end
    end
    return false unless inspect_value.call(value, 0)
    return false if JSON.generate(value).bytesize > 32_768

    identifier = value["id"] || value[:id]
    !revision || valid_processing_identifier?(identifier)
  rescue JSON::GeneratorError, EncodingError
    false
  end

  def self.valid_processing_identifier?(value)
    value.is_a?(String) && value.valid_encoding? && value.strip.present? && value.length <= 200
  end

  # Strips any directory component and replaces characters outside a
  # conservative set, so a stored name is safe in a download header.
  def self.sanitize_filename(filename)
    text = filename.to_s.dup.force_encoding(Encoding::UTF_8).scrub("_")
    base_name = File.basename(text.tr("\\", "/"))
    cleaned = base_name.gsub(/[^\w.\- ]/, "_").sub(/\A[.\s]+/, "").strip
    cleaned = cleaned.first(255)
    cleaned.presence || "upload"
  end

  # Display reference derived from the primary key, not a stored column.
  def reference
    return nil unless persisted?

    format("RFQ-%04d", id)
  end

  def subtotal
    quote_lines.to_a.select(&:quotable?).sum(BigDecimal("0")) { |line| line.line_total }
  end

  def ready_count
    quote_lines.to_a.count(&:quotable?)
  end

  def held_count
    quote_lines.to_a.count { |line| !line.quotable? }
  end

  def approved?
    approved_at.present?
  end

  def due_at
    created_at && created_at + 24.hours
  end

  # Delivery belongs to a reviewed revision. A later edit needs a new send;
  # approval or opening a local mail preview never records a delivery.
  def sent?
    approved? && sent_at.present? && sent_review_revision.present? && sent_review_revision == review_revision
  end

  def sent_metadata_shape
    return if sent_at.nil? && sent_review_revision.nil?

    errors.add(:sent_review_revision, "must identify the sent revision") unless self.class.valid_processing_identifier?(sent_review_revision)
    errors.add(:sent_at, "must be a delivery time on or after receipt") unless sent_at && (!created_at || sent_at >= created_at)
  end

  def awaiting_processing?
    quote_lines.empty?
  end

  # Approval needs at least one quotable line, and every held line must carry
  # a question for the buyer, so nothing is held silently.
  def approvable?
    lines = quote_lines.to_a
    return false unless lines.any?(&:quotable?)

    lines.reject(&:quotable?).all? { |line| line.clarification_question.present? }
  end

  def review_revision
    updated_at&.iso8601(6)
  end

  def approve!(approved_time: Time.current, expected_revision: nil)
    with_lock do
      if !expected_revision.nil? && expected_revision != review_revision
        raise StaleReview, "The quote changed since your review. Review it again before approving."
      end

      quote_lines.reset
      raise NotApprovable, "Quote #{reference} is not ready for approval" unless approvable?

      update_columns(approved_at: approved_time, updated_at: next_review_timestamp)
    end
  end

  # Callers that mutate lines take this same quote lock before writing them.
  # Touch even an unapproved quote so every saved edit invalidates stale reviews.
  def invalidate_approval!
    with_lock do
      update_columns(approved_at: nil, updated_at: next_review_timestamp)
    end
  end

  def source_file?
    source_bytes.present?
  end

  private

  def processing_evidence_shape
    self.class.processing_evidence_errors(source: processing_source, warnings: processing_warnings).each do |problem|
      errors.add(:base, "Extraction metadata: #{problem}")
    end
  end

  def processing_revision_shape
    unless self.class.valid_processing_metadata?(processing_revision, revision: true)
      errors.add(:processing_revision, "must be bounded JSON with a nonblank revision id")
    end
  end

  def next_review_timestamp
    now = Time.current
    updated_at ? [ now, updated_at + Rational(1, 1_000_000) ].max : now
  end

  def source_present
    return if source_text.present? || source_bytes.present?

    errors.add(:source_text, "is empty. Paste the RFQ text or attach a file")
  end

  def source_bytes_within_limit
    return if source_bytes.nil?
    return if source_bytes.bytesize <= MAXIMUM_SOURCE_BYTES

    errors.add(:source_bytes, "must be 10 MB or smaller")
  end

  def original_filename_present_with_file
    return if source_bytes.nil? || original_filename.present?

    errors.add(:original_filename, "is required for an attached file")
  end
end
