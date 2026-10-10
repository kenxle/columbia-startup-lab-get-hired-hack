# One client's meaning for a word or phrase, such as "KB" meaning a #4 finish
# or "16 ga" meaning 0.0625 in for this buyer.
# "taught" terms come from the rep; "learned" terms come from approved matches.
#
# meaning: {"fields" => {"finish" => "#4"}, "part_number" => "...",
#           "confirmed_on" => "RFQ-0001"}. confirmed_on names the RFQ where the
# meaning was confirmed, so a later quote can say where it came from.
class ClientTerm < ApplicationRecord
  SOURCES = %w[taught learned].freeze
  TEXT_FIELDS = %w[material grade temper form finish standard quantity_unit].freeze
  NUMBER_FIELDS = %w[gauge thickness].freeze
  TEACHABLE_FIELDS = (TEXT_FIELDS + NUMBER_FIELDS).freeze

  belongs_to :client

  normalizes :term, with: ->(term) { term.to_s.squish.downcase }

  validates :term, presence: true, length: { maximum: 120 }, uniqueness: { scope: :client_id }
  validates :source, inclusion: { in: SOURCES }
  validate :meaning_shape

  # Values typed the way the reader uses them: gauge an integer, thickness inches.
  def field_values
    raw = meaning.is_a?(Hash) ? meaning.fetch("fields", {}).slice(*TEACHABLE_FIELDS) : {}
    raw.to_h { |field, value| [ field, self.class.cast(field, value) ] }.compact
  end

  def part_number
    meaning.is_a?(Hash) ? meaning["part_number"].presence : nil
  end

  def confirmed_on
    meaning.is_a?(Hash) ? meaning["confirmed_on"].presence : nil
  end

  def explanation_prefix
    how = source == "taught" ? "taught by the rep" : "learned from #{times_confirmed} approved #{'request'.pluralize(times_confirmed)}"
    how += ", confirmed on #{confirmed_on}" if confirmed_on
    "#{client.name} (#{how}):"
  end

  def describe
    parts = field_values.map { |field, value| "#{field} #{value}" }
    parts << part_number if part_number
    parts.join(", ")
  end

  # "16" -> 16 for gauge; "0.0625" or "1/16" -> 0.0625 for thickness (inches).
  def self.cast(field, value)
    return value.to_s.strip.presence unless NUMBER_FIELDS.include?(field)

    text = value.to_s.strip.delete_suffix("in").delete_suffix("ga").strip
    number = if (parts = text.match(%r{\A(\d+)/(\d+)\z})) then parts[1].to_f / parts[2].to_f
             else Float(text, exception: false)
             end
    return nil if number.nil? || !number.positive?

    field == "gauge" ? (number == number.round ? number.to_i : nil) : number
  end

  private

  def meaning_shape
    unless meaning.is_a?(Hash) && (field_values.any? || part_number)
      errors.add(:meaning, "must name a part number or at least one valid field value")
      return
    end
    raw = meaning.fetch("fields", {})
    unknown = raw.keys - TEACHABLE_FIELDS
    errors.add(:meaning, "has fields that cannot be taught: #{unknown.join(', ')}") if unknown.any?
    invalid = raw.slice(*NUMBER_FIELDS).select { |field, value| self.class.cast(field, value).nil? }.keys
    errors.add(:meaning, "needs a positive number for #{invalid.join(', ')}") if invalid.any?
    errors.add(:meaning, "confirmed_on is too long") if confirmed_on.to_s.length > 40
  end
end
