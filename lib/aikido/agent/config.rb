# frozen_string_literal: true

require "uri"
require "json"
require "logger"

require_relative "request"

module Aikido::Agent
  class Config
    # @return [Boolean] whether Aikido should only report infractions or block
    #   the request by raising an Exception. Defaults to whether AIKIDO_BLOCKING
    #   is set to a non-empty value in your environment, or +false+ otherwise.
    attr_accessor :blocking_mode
    alias_method :blocking_mode?, :blocking_mode

    # @return [URI] The HTTP host for the Aikido API. Defaults to
    #   +https://guard.aikido.dev+.
    attr_reader :api_base_url

    # @return [URI] The HTTP host for the Aikido Runtime API. Defaults to
    #   +https://runtime.aikido.dev+.
    attr_reader :runtime_api_base_url

    # @return [Hash] HTTP timeouts for communicating with the API.
    attr_reader :api_timeouts

    # @return [String] the token obtained when configuring the Firewall in the
    #   Aikido interface.
    attr_accessor :api_token

    # @return [Integer] the interval in seconds to poll the runtime API for
    #   settings changes. Defaults to evey 60 seconds.
    attr_accessor :polling_interval

    # @return [#call] Callable that can be passed an Object and returns a String
    #   of JSON. Defaults to the standard library's JSON.dump method.
    attr_accessor :json_encoder

    # @return [#call] Callable that can be passed a JSON string and parses it
    #   into an Object. Defaults to the standard library's JSON.parse method.
    attr_accessor :json_decoder

    # @returns [Logger]
    attr_accessor :logger

    # @return [Integer] maximum number of timing measurements to keep in memory
    #   before compressing them.
    attr_accessor :max_performance_samples

    # @return [Integer] maximum number of compressed performance samples to keep
    #   in memory. If we take more than this before reporting them to Aikido, we
    #   will discard the oldest samples.
    attr_accessor :max_compressed_stats

    # @api internal
    # @return [Proc<Hash => Aikido::Agent::Request>] callable that takes a
    #   Rack-compatible env Hash and returns a Request object. This is meant
    #   to be overridden by each framework adapter.
    attr_accessor :request_builder

    def initialize
      self.blocking_mode = !!ENV.fetch("AIKIDO_BLOCKING", false)
      self.api_timeouts = 10
      self.api_base_url = ENV.fetch("AIKIDO_BASE_URL", DEFAULT_API_BASE_URL)
      self.runtime_api_base_url = ENV.fetch("AIKIDO_RUNTIME_URL", DEFAULT_RUNTIME_BASE_URL)
      self.api_token = ENV.fetch("AIKIDO_TOKEN", nil)
      self.polling_interval = 60
      self.json_encoder = DEFAULT_JSON_ENCODER
      self.json_decoder = DEFAULT_JSON_DECODER
      self.logger = Logger.new($stdout, progname: "aikido")
      self.max_performance_samples = 5000
      self.max_compressed_stats = 100
      self.request_builder = Aikido::Agent::Request::RACK_REQUEST_BUILDER
    end

    # Set the base URL for API requests.
    #
    # @param url [String, URI]
    def api_base_url=(url)
      @api_base_url = URI(url)
    end

    # Set the base URL for runtime API requests.
    #
    # @param url [String, URI]
    def runtime_api_base_url=(url)
      @runtime_api_base_url = URI(url)
    end

    # @overload def api_timeouts=(timeouts)
    #   Configure granular connection timeouts for the Aikido Firewall API. You
    #   can set any of these per call.
    #   @param timeouts [Hash]
    #   @option timeouts [Integer] :open_timeout Duration in seconds.
    #   @option timeouts [Integer] :read_timeout Duration in seconds.
    #   @option timeouts [Integer] :write_timeout Duration in seconds.
    #
    # @overload def api_timeouts=(duration)
    #   Configure the connection timeouts for the Aikido Firewall API.
    #   @param duration [Integer] Duration in seconds to set for all three
    #     timeouts (open, read, and write).
    def api_timeouts=(value)
      value = {open_timeout: value, read_timeout: value, write_timeout: value} if value.respond_to?(:to_int)

      @api_timeouts ||= {}
      @api_timeouts.update(value)
    end

    # @!visibility private
    DEFAULT_API_BASE_URL = "https://guard.aikido.dev"

    # @!visibility private
    DEFAULT_RUNTIME_BASE_URL = "https://runtime.aikido.dev"

    # @!visibility private
    DEFAULT_JSON_ENCODER = JSON.method(:dump)

    # @!visibility private
    DEFAULT_JSON_DECODER = JSON.method(:parse)
  end
end
