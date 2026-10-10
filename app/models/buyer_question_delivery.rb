class BuyerQuestionDelivery < ApplicationRecord
  belongs_to :quote
  belongs_to :quote_line, optional: true

  scope :previewed, -> { where(status: "previewed", channel: "local_preview").where.not(previewed_at: nil) }

  validates :fingerprint, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :channel, inclusion: { in: ["local_preview"] }
  validates :status, inclusion: { in: %w[pending previewed failed] }
  validates :recipient, inclusion: { in: ["buyer@example.invalid"] }
  validates :question_text, presence: true, length: { maximum: 1_000 }
  validates :line_position, numericality: { only_integer: true, greater_than: 0 }
end
