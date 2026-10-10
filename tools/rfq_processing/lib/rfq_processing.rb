# frozen_string_literal: true

# RFQ processing: turns a messy RFQ into the result hash the quote app accepts.
# Owner: Yuval. Plain Ruby, no Rails. See docs/rfq_processing/RESULT-FORMAT.md.
module RfqProcessing
  VERSION = "0.1.0"
  SCHEMA_VERSION = 1
end

Dir[File.join(__dir__, "rfq_processing", "*.rb")].sort.each { |file| require file }
