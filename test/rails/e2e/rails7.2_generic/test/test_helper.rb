# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "net/http"
require "json"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Polls +block+ every +interval+ seconds until it returns a truthy value,
    # then returns that value, instead of sleeping for a worst-case duration.
    #
    # @param timeout [Numeric] maximum seconds to wait before raising
    # @param interval [Numeric] seconds to sleep between attempts
    # @return [Object] the truthy value returned by +block+
    # @raise [RuntimeError] if no attempt succeeds within +timeout+ seconds
    def poll_until(timeout: 10, interval: 0.25)
      deadline = Time.now + timeout
      loop do
        result = yield
        return result if result

        raise "Condition not met within #{timeout}s" if Time.now > deadline

        sleep interval
      end
    end
  end
end

# Helpers for interacting with the Rails app under test.
#
# Optional env vars:
#   RAILS_SERVER_URI  - base URI of the Rails server (default: http://127.0.0.1:3000)
module RailsServerHelpers
  RAILS_SERVER_URI = ENV.fetch("RAILS_SERVER_URI", "http://127.0.0.1:3000")

  # @param path [String] path and query string to request
  # @return [Net::HTTPResponse]
  def rails_get(path)
    Net::HTTP.get_response(URI("#{RAILS_SERVER_URI}#{path}"))
  end
end

# Helpers for interacting with the mock Aikido API server that runs alongside
# the Rails app under test.
#
# Required env vars (set by the ci:e2e rake task):
#   MOCK_SERVER_URI  - base URI of the mock server (default: http://127.0.0.1:4567)
#   MOCK_TOKEN       - bearer token registered with the mock before Rails started
module MockServerHelpers
  MOCK_SERVER_URI = ENV.fetch("MOCK_SERVER_URI", "http://127.0.0.1:4567")
  MOCK_TOKEN = ENV.fetch("MOCK_TOKEN", nil)

  # @param type [String, nil] if given, only events of this type are returned
  # @return [Array<Hash>] events captured by the mock server for our app token
  def received_events(type: nil)
    raise "MOCK_TOKEN is not set - run tests via `rake ci:e2e`" unless MOCK_TOKEN

    uri = URI("#{MOCK_SERVER_URI}/api/runtime/events")

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = MOCK_TOKEN

    response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }

    events = JSON.parse(response.body)

    type ? events.select { |e| e["type"] == type } : events
  end

  # Polls until at least one event of +type+ appears after +after_index+, then
  # returns all such events.
  #
  # @param type [String] event type to wait for
  # @param after_index [Integer] skip events at or before this index
  # @param timeout [Integer] maximum seconds to wait before raising
  # @return [Array<Hash>] the new events of +type+ that arrived
  # @raise [RuntimeError] if no matching event arrives within +timeout+ seconds
  def wait_for_event(type:, after_index: 0, timeout: 10)
    deadline = Time.now + timeout
    loop do
      events = received_events(type: type)

      fresh = events[after_index..]
      return fresh if fresh&.any?

      if Time.now > deadline
        raise "Timed out after #{timeout}s waiting for a '#{type}' event " \
          "(#{events.length} total '#{type}' events seen)"
      end

      sleep 0.25
    end
  end

  # Updates runtime settings on the mock server.
  #
  # @param attrs [Hash] settings to merge into the mock's runtime config
  # @return [void]
  def configure_mock(attrs)
    raise "MOCK_TOKEN is not set - run tests via `rake ci:e2e`" unless MOCK_TOKEN

    uri = URI("#{MOCK_SERVER_URI}/api/runtime/config")

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = MOCK_TOKEN
    request["Content-Type"] = "application/json"
    request.body = JSON.dump(attrs)

    Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
  end

  # Updates the mock's firewall lists (blocked/allowed IPs, user agents, etc.)
  #
  # @param attrs [Hash] firewall list attributes to update
  # @return [void]
  def configure_mock_firewall_lists(attrs)
    raise "MOCK_TOKEN is not set - run tests via `rake ci:e2e`" unless MOCK_TOKEN

    uri = URI("#{MOCK_SERVER_URI}/api/runtime/firewall/lists")

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = MOCK_TOKEN
    request["Content-Type"] = "application/json"
    request.body = JSON.dump(attrs)

    Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
  end
end
