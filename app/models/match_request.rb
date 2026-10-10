# One description a client sent, what the matcher suggested, and what the rep
# approved. Kept so the client's memory can learn from approvals.
class MatchRequest < ApplicationRecord
  OUTCOMES = %w[match candidates no_match].freeze

  belongs_to :client

  attribute :approved_part_numbers, default: -> { [] }

  validates :description, presence: true, length: { maximum: 2_000 }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :quantity, numericality: { greater_than: 0 }, allow_nil: true

  def approved?
    approved_at.present?
  end

  def suggested_part_numbers
    Array(result["candidates"]).map { |candidate| candidate["pn"] }
  end
end
