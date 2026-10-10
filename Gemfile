source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Generate portable quote PDFs without a browser or external renderer.
gem "prawn", "~> 2.5"
# Excel (.xlsx) RFQ intake, read lazily by tools/rfq_processing Extractor.from_xlsx
gem "roo", "~> 2.10", require: false
gem "csv", "~> 3.3"
gem "pdf-reader", "~> 2.16"
gem "anthropic"
gem "dotenv-rails", groups: %i[development test]

group :development do
  gem "letter_opener", "~> 1.10"
end

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end

gem "minitest-mock", "~> 5.27", group: :test
