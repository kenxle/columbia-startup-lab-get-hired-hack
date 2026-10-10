class ProcessingRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed stale conflict].freeze
  ACTIVE_STATUSES = %w[queued running].freeze

  belongs_to :quote
  validates :status, inclusion: { in: STATUSES }
  validates :requested_revision, :source_revision, :queued_at, presence: true
  validates :error_message, length: { maximum: 1_000 }
  validates :source_filename, length: { maximum: 255 }

  def active?
    ACTIVE_STATUSES.include?(status)
  end
end
