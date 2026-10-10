ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Keep the small local suite portable; opt into parallel workers when needed.
    parallelize(workers: ENV.fetch("PARALLEL_WORKERS", "1").to_i)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
