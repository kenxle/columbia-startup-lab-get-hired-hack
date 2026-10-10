# frozen_string_literal: true

module RfqProcessing
  # Numbers and units as buyers write them: 1/8, 1-1/2, 1 1/2, .188, 0.060, 24', 20ft, 48".
  module Units
    MIXED = %r{\A(\d+)[\s-](\d+)\s*/\s*(\d+)\z}
    FRACTION = %r{\A(\d+)\s*/\s*(\d+)\z}
    DECIMAL = /\A(\d*\.\d+|\d+(?:\.\d+)?)\z/

    INCH_MARKS = /\A(?:"|”|''|in\.?|inch(?:es)?)\z/i
    FOOT_MARKS = /\A(?:'|’|ft\.?|feet|foot)\z/i
    MM_MARKS = /\A(?:mm)\z/i

    # "1-1/2" -> 1.5, "3/16" -> 0.1875, ".188" -> 0.188, "48" -> 48.0. Nil when not a number.
    def self.parse_number(text)
      text = text.to_s.strip
      if (m = MIXED.match(text))
        m[1].to_f + m[2].to_f / m[3].to_f
      elsif (m = FRACTION.match(text))
        m[1].to_f / m[2].to_f
      elsif DECIMAL.match?(text)
        text.to_f
      end
    end

    # Unit token to :in, :ft, :mm, or nil.
    def self.unit_of(token)
      return nil if token.nil? || token.empty?
      return :in if INCH_MARKS.match?(token)
      return :ft if FOOT_MARKS.match?(token)
      return :mm if MM_MARKS.match?(token)

      nil
    end

    def self.to_inches(value, unit)
      case unit
      when :ft then value * 12.0
      when :mm then value / 25.4
      else value
      end
    end

    # Round for display and comparison. 0.0625 stays 0.0625; 48.0 becomes 48.
    def self.tidy(value)
      return nil if value.nil?

      rounded = value.round(5)
      rounded == rounded.to_i ? rounded.to_i : rounded
    end
  end
end
