# frozen_string_literal: true

require "uri"
require "json"
require "logger"

require_relative "context"

module Aikido::Zen
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

    # @return [Integer] the amount in seconds to wait before sending an initial
    #   heartbeat event when the server reports no stats have been sent yet.
    attr_accessor :initial_heartbeat_delay

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

    # @return [Integer] maximum number of connections to outbound hosts to keep
    #   in memory in order to report them in the next heartbeat event. If new
    #   connections are added to the set before reporting them to Aikido, we
    #   will discard the oldest data point.
    attr_accessor :max_outbound_connections

    # @return [Integer] maximum number of users tracked via Zen.track_user to
    #   share with the Aikido servers on the next heartbeat event. If more
    #   unique users (by their ID) are tracked than this number, we will discard
    #   the oldest seen users.
    attr_accessor :max_users_tracked

    # @return [Hash<Symbol, Symbol>] maps which attributes we should read
    #   from a "user" object when converting it to an Aikido::Zen::Actor.
    # @see Aikido::Zen.Actor
    attr_reader :user_attribute_mappings

    # @api internal
    # @return [Proc<Hash => Aikido::Zen::Context>] callable that takes a
    #   Rack-compatible env Hash and returns a Context object with an HTTP
    #   request. This is meant to be overridden by each framework adapter.
    attr_accessor :request_builder

    # @return [Proc{Aikido::Zen::Request => Array(Integer, Hash, #each)}]
    #   Rack handler used to respond to requests from IPs blocked in the Aikido
    #   dashboard.
    attr_accessor :blocked_ip_responder

    # @return [Proc{Aikido::Zen::Request => Array(Integer, Hash, #each)}]
    #   Rack handler used to respond to requests that have been rate limited.
    attr_accessor :rate_limited_responder

    # @return [Proc{Aikido::Zen::Request => String}] a proc that reads
    #   information off the current request and returns a String to
    #   differentiate different clients. By default this uses the request IP.
    attr_accessor :rate_limiting_discriminator

    def initialize
      self.blocking_mode = !!ENV.fetch("AIKIDO_BLOCKING", false)
      self.api_timeouts = 10
      self.api_base_url = ENV.fetch("AIKIDO_BASE_URL", DEFAULT_API_BASE_URL)
      self.runtime_api_base_url = ENV.fetch("AIKIDO_RUNTIME_URL", DEFAULT_RUNTIME_BASE_URL)
      self.api_token = ENV.fetch("AIKIDO_TOKEN", nil)
      self.polling_interval = 60
      self.initial_heartbeat_delay = 60
      self.json_encoder = DEFAULT_JSON_ENCODER
      self.json_decoder = DEFAULT_JSON_DECODER
      self.logger = Logger.new($stdout, progname: "aikido")
      self.max_performance_samples = 5000
      self.max_compressed_stats = 100
      self.max_outbound_connections = 200
      self.max_users_tracked = 1000
      self.request_builder = Aikido::Zen::Context::RACK_REQUEST_BUILDER
      self.blocked_ip_responder = DEFAULT_BLOCKED_IP_RESPONDER
      self.rate_limited_responder = DEFAULT_RATE_LIMITED_RESPONDER
      self.rate_limiting_discriminator = DEFAULT_RATE_LIMITING_DISCRIMINATOR
      @user_attribute_mappings = {id: :id, name: :name}
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
    #   Configure granular connection timeouts for the Aikido Zen API. You
    #   can set any of these per call.
    #   @param timeouts [Hash]
    #   @option timeouts [Integer] :open_timeout Duration in seconds.
    #   @option timeouts [Integer] :read_timeout Duration in seconds.
    #   @option timeouts [Integer] :write_timeout Duration in seconds.
    #
    # @overload def api_timeouts=(duration)
    #   Configure the connection timeouts for the Aikido Zen API.
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

    # @!visibility private
    DEFAULT_BLOCKED_IP_RESPONDER = ->(request) do
      message = "Your IP address is not allowed to access this resource. (Your IP: %s)"
      [403, {"Content-Type" => "text/plain"}, [format(message, request.ip)]]
    end

    # @!visibility private
    DEFAULT_RATE_LIMITED_RESPONDER = ->(request) do
      [429, {"Content-Type" => "text/plain"}, ["Too many requests."]]
    end

    # @!visibility private
    DEFAULT_RATE_LIMITING_DISCRIMINATOR = ->(request) { request.ip }
  end
end
