# One client's meaning for a word or phrase, such as "KB" meaning a #4 finish.
# "taught" terms come from the rep; "learned" terms come from approved matches.
class ClientTerm < ApplicationRecord
  SOURCES = %w[taught learned].freeze
  TEACHABLE_FIELDS = %w[material grade temper form finish standard].freeze

  belongs_to :client

  normalizes :term, with: ->(term) { term.to_s.squish.downcase }

  validates :term, presence: true, length: { maximum: 120 }, uniqueness: { scope: :client_id }
  validates :source, inclusion: { in: SOURCES }
  validate :meaning_shape

  def field_values
    meaning.is_a?(Hash) ? meaning.fetch("fields", {}).slice(*TEACHABLE_FIELDS) : {}
  end

  def part_number
    meaning.is_a?(Hash) ? meaning["part_number"].presence : nil
  end

  def explanation_prefix
    how = source == "taught" ? "taught by the rep" : "learned from #{times_confirmed} approved #{'request'.pluralize(times_confirmed)}"
    "#{client.name} (#{how}):"
  end

  def describe
    parts = field_values.map { |field, value| "#{field} #{value}" }
    parts << part_number if part_number
    parts.join(", ")
  end

  private

  def meaning_shape
    unless meaning.is_a?(Hash) && (field_values.any? || part_number)
      errors.add(:meaning, "must name a part number or at least one field value")
      return
    end
    unknown = meaning.fetch("fields", {}).keys - TEACHABLE_FIELDS
    errors.add(:meaning, "has fields that cannot be taught: #{unknown.join(', ')}") if unknown.any?
  end
end
