class Quote < ApplicationRecord
  MAXIMUM_SOURCE_BYTES = 10.megabytes
  MAXIMUM_SOURCE_TEXT_LENGTH = 50_000
  ALLOWED_UPLOAD_EXTENSIONS = %w[.pdf .xlsx .xls .csv .txt .eml].freeze

  class NotApprovable < StandardError; end
  class StaleReview < NotApprovable; end

  has_many :quote_lines, -> { order(:position) }, dependent: :delete_all, inverse_of: :quote

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
