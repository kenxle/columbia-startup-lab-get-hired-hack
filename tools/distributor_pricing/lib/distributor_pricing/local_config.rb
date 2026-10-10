# frozen_string_literal: true

module DistributorPricing
  module LocalConfig
    ALLOWED = %w[NINOO_API_KEY NINOO_MODEL DISTRIBUTOR_PROCUREMENT_FEED].freeze

    def self.read(root: File.expand_path("../../../..", __dir__))
      path = File.join(root, ".env")
      local = File.file?(path) ? File.read(path).lines.filter_map do |line|
        key, value = line.strip.split("=", 2)
        [key, value] if ALLOWED.include?(key) && value
      end.to_h : {}
      ALLOWED.to_h { |key| [key, ENV[key] || local[key]] }
    end
  end
end
