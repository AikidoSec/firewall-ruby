# frozen_string_literal: true

require "uri"
require "json"
require "logger"
require "digest"

require_relative "context"

module Aikido::Zen
  class Config
    # @return [Class, Integer, nil] The Rack middleware class or index after which
    #   the Zen middleware should be inserted. When set to nil, the middleware is
    #   inserted before the first middleware in the then-current middleware stack.
    #   Defaults to ::ActionDispatch::Executor.
    attr_accessor :insert_middleware_after

    # @return [Boolean] whether Aikido should be turned completely off (no
    #   intercepting calls to protect the app, no agent process running, no
    #   middleware installed). Defaults to false (so, enabled). Can be set
    #   via the AIKIDO_DISABLE environment variable.
    attr_accessor :disabled
    alias_method :disabled?, :disabled

    # @return [Boolean] whether Aikido should only report infractions or block
    #   the request by raising an Exception. Defaults to whether AIKIDO_BLOCK
    #   is set to a non-empty value in your environment, or +false+ otherwise.
    attr_accessor :blocking_mode
    alias_method :blocking_mode?, :blocking_mode

    # @return [URI] The HTTP host for the Aikido API. Defaults to
    #   +https://guard.aikido.dev+.
    attr_reader :api_endpoint

    # @return [URI] The HTTP host for the Aikido Runtime API. Defaults to
    #   +https://runtime.aikido.dev+.
    attr_reader :realtime_endpoint

    # @return [Hash] HTTP timeouts for communicating with the API.
    attr_reader :api_timeouts

    # @return [String] the token obtained when configuring the Firewall in the
    #   Aikido interface.
    attr_accessor :api_token

    # @return [Integer] the interval in seconds to poll the runtime API for
    #   settings changes. Defaults to evey 60 seconds.
    attr_accessor :polling_interval

    # @return [Array<Integer>] the delays in seconds to wait before sending
    #   each initial heartbeat event.
    attr_accessor :initial_heartbeat_delays

    # @return [#call] Callable that can be passed an Object and returns a String
    #   of JSON. Defaults to the standard library's JSON.dump method.
    attr_accessor :json_encoder

    # @return [#call] Callable that can be passed a JSON string and parses it
    #   into an Object. Defaults to the standard library's JSON.parse method.
    attr_accessor :json_decoder

    # @return [Logger]
    attr_reader :logger

    # @return [String] Path of the socket where the detached agent will listen.
    # By default, the socket file is created in the current working directory.
    # Defaults to `aikido-detached-agent.sock`.
    attr_accessor :detached_agent_socket_path

    # @return [Boolean] is the agent in debugging mode?
    attr_accessor :debugging
    alias_method :debugging?, :debugging

    # @return [String] environment specific HTTP header providing the client IP.
    attr_accessor :client_ip_header

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

    # @return [Proc{(Aikido::Zen::Request, Symbol) => Array(Integer, Hash, #each)}]
    #   Rack handler used to respond to requests from IPs, users or others blocked in the Aikido
    #   dashboard.
    attr_accessor :blocked_responder

    # @return [Proc{Aikido::Zen::Request => Array(Integer, Hash, #each)}]
    #   Rack handler used to respond to requests that have been rate limited.
    attr_accessor :rate_limited_responder

    # @return [Proc{Aikido::Zen::Request => String}] a proc that reads
    #   information off the current request and returns a String to
    #   differentiate different clients. By default this uses the request IP.
    attr_accessor :rate_limiting_discriminator

    # @return [Boolean] whether Aikido Zen should collect api schemas.
    #   Defaults to true. Can be set through AIKIDO_FEATURE_COLLECT_API_SCHEMA
    #   environment variable.
    attr_accessor :collect_api_schema
    alias_method :collect_api_schema?, :collect_api_schema

    # @return [Integer] max number of requests we sample per endpoint when
    #   computing the schema.
    attr_accessor :api_schema_max_samples

    # @api private
    # @return [Integer] max number of levels deep we want to read a nested
    #   strcture for performance reasons.
    attr_accessor :api_schema_collection_max_depth

    # @api private
    # @return [Integer] max number of properties that we want to inspect per
    #   level of the structure for performance reasons.
    attr_accessor :api_schema_collection_max_properties

    # @api private
    # @return [Proc<Hash => Aikido::Zen::Context>] callable that takes a
    #   Rack-compatible env Hash and returns a Context object with an HTTP
    #   request. This is meant to be overridden by each framework adapter.
    attr_accessor :request_builder

    # @api private
    # @return [Integer] number of seconds to perform client-side rate limiting
    #   of events sent to the server.
    attr_accessor :client_rate_limit_period

    # @api private
    # @return [Integer] max number of events sent during a sliding
    #   {client_rate_limit_period} window.
    attr_accessor :client_rate_limit_max_events

    # @api private
    # @return [Integer] number of seconds to wait before sending an event after
    #   the server returns a 429 response.
    attr_accessor :server_rate_limit_deadline

    # @return [Boolean] whether Aikido Zen should scan for stored SSSRF attacks.
    #   Defaults to true. Can be set through AIKIDO_FEATURE_STORED_SSRF
    #   environment variable.
    attr_accessor :stored_ssrf
    alias_method :stored_ssrf?, :stored_ssrf

    # @return [Array<String>] when checking for stored SSRF attacks, we want to
    #   allow known hosts that should be able to resolve to the IMDS service.
    attr_accessor :imds_allowed_hosts

    # @return [Boolean] whether Aikido Zen should harden methods where possible.
    #   Defaults to true. Can be set through AIKIDO_HARDEN environment variable.
    attr_accessor :harden
    alias_method :harden?, :harden

    # @return [Integer] how many suspicious requests are allowed before an
    #   attack wave detected event is reported.
    #   Defaults to 15 requests.
    attr_accessor :attack_wave_threshold

    # @return [Integer] the minimum time in milliseconds between requests for
    #   requests to be part of an attack wave.
    #   Defaults to 1 minute in milliseconds.
    attr_accessor :attack_wave_min_time_between_requests

    # @return [Integer] the minimum time in milliseconds between reporting
    #   attack wave events.
    #   Defaults to 20 minutes in milliseconds.
    attr_accessor :attack_wave_min_time_between_events

    # @return [Integer] the maximum number of entries in the LRU cache.
    #   Defaults to 10,000 entries.
    attr_accessor :attack_wave_max_cache_entries

    # @return [Integer] the maximum number of samples in the LRU cache.
    #   Defaults to 15 entries.
    attr_accessor :attack_wave_max_cache_samples

    def initialize
      self.insert_middleware_after = ::ActionDispatch::Executor
      self.disabled = read_boolean_from_env(ENV.fetch("AIKIDO_DISABLE", false)) || read_boolean_from_env(ENV.fetch("AIKIDO_DISABLED", false))
      self.blocking_mode = read_boolean_from_env(ENV.fetch("AIKIDO_BLOCK", false))
      self.api_timeouts = 10
      self.api_endpoint = ENV.fetch("AIKIDO_ENDPOINT", DEFAULT_AIKIDO_ENDPOINT)
      self.realtime_endpoint = ENV.fetch("AIKIDO_REALTIME_ENDPOINT", DEFAULT_RUNTIME_BASE_URL)
      self.api_token = ENV.fetch("AIKIDO_TOKEN", nil)
      self.polling_interval = 60 # 1 min
      self.initial_heartbeat_delays = [30, 60 * 2] # 30 sec, 2 min
      self.json_encoder = DEFAULT_JSON_ENCODER
      self.json_decoder = DEFAULT_JSON_DECODER
      self.debugging = read_boolean_from_env(ENV.fetch("AIKIDO_DEBUG", false))
      self.logger = Logger.new($stdout, progname: "aikido", level: debugging ? Logger::DEBUG : Logger::INFO)
      self.detached_agent_socket_path = ENV.fetch("AIKIDO_DETACHED_AGENT_SOCKET_PATH", DEFAULT_DETACHED_AGENT_SOCKET_PATH)
      self.client_ip_header = ENV.fetch("AIKIDO_CLIENT_IP_HEADER", nil)
      self.max_performance_samples = 5000
      self.max_compressed_stats = 100
      self.max_outbound_connections = 200
      self.max_users_tracked = 1000
      self.request_builder = Aikido::Zen::Context::RACK_REQUEST_BUILDER
      self.blocked_responder = DEFAULT_BLOCKED_RESPONDER
      self.rate_limited_responder = DEFAULT_RATE_LIMITED_RESPONDER
      self.rate_limiting_discriminator = DEFAULT_RATE_LIMITING_DISCRIMINATOR
      self.server_rate_limit_deadline = 30 * 60 # 30 min
      self.client_rate_limit_period = 60 * 60 # 1 hour
      self.client_rate_limit_max_events = 100
      self.collect_api_schema = read_boolean_from_env(ENV.fetch("AIKIDO_FEATURE_COLLECT_API_SCHEMA", true))
      self.api_schema_max_samples = Integer(ENV.fetch("AIKIDO_MAX_API_DISCOVERY_SAMPLES", 10))
      self.api_schema_collection_max_depth = 20
      self.api_schema_collection_max_properties = 20
      self.stored_ssrf = read_boolean_from_env(ENV.fetch("AIKIDO_FEATURE_STORED_SSRF", true))
      self.imds_allowed_hosts = ["metadata.google.internal", "metadata.goog"]
      self.harden = read_boolean_from_env(ENV.fetch("AIKIDO_HARDEN", true))
      self.attack_wave_threshold = 15
      self.attack_wave_min_time_between_requests = 60 * 1000 # 1 min (ms)
      self.attack_wave_min_time_between_events = 20 * 60 * 1000 # 20 min (ms)
      self.attack_wave_max_cache_entries = 10_000
      self.attack_wave_max_cache_samples = 15
    end

    # Set the base URL for API requests.
    #
    # @param url [String, URI]
    def api_endpoint=(url)
      @api_endpoint = URI(url)
    end

    # Set the base URL for runtime API requests.
    #
    # @param url [String, URI]
    def realtime_endpoint=(url)
      @realtime_endpoint = URI(url)
    end

    # Set the logger and configure its severity level according to agent's debug mode
    # @param logger [::Logger]
    def logger=(logger)
      @logger = logger
      @logger.level = Logger::DEBUG if debugging
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

    def api_token_hash
      return unless api_token

      @api_token_hash ||= Digest::SHA1.hexdigest(api_token)[0, 7]
    end

    def detached_agent_socket_uri
      "drbunix:" + @detached_agent_socket_path
    end

    def expanded_detached_agent_socket_path
      @exanded_detached_agent_path ||= expand_socket_path(detached_agent_socket_path)
    end

    def expanded_detached_agent_socket_uri
      @exanded_detached_agent_uri ||= expand_socket_path(detached_agent_socket_uri)
    end

    private

    def expand_socket_path(socket_path)
      socket_path = socket_path.dup
      socket_path.gsub!("%h", api_token_hash) if api_token_hash
      socket_path
    end

    def read_boolean_from_env(value)
      return value unless value.respond_to?(:to_str)

      case value.to_str.strip
      when "false", "", "0", "f"
        false
      else
        true
      end
    end

    # @!visibility private
    DEFAULT_AIKIDO_ENDPOINT = "https://guard.aikido.dev"

    # @!visibility private
    DEFAULT_RUNTIME_BASE_URL = "https://runtime.aikido.dev"

    # @!visibility private
    DEFAULT_JSON_ENCODER = JSON.method(:dump)

    # @!visibility private
    DEFAULT_JSON_DECODER = JSON.method(:parse)

    # @!visibility private
    DEFAULT_DETACHED_AGENT_SOCKET_PATH = "aikido-detached-agent.%h.sock"

    # @!visibility private
    DEFAULT_BLOCKED_RESPONDER = ->(request, blocking_type) do
      message = case blocking_type
      when :ip
        format("Your IP address is not allowed to access this resource. (Your IP: %s)", request.ip)
      when :user_agent
        "You are not allowed to access this resource because you have been identified as a bot."
      else
        "You are blocked by Zen."
      end
      [403, {"Content-Type" => "text/plain"}, [message]]
    end

    # @!visibility private
    DEFAULT_RATE_LIMITED_RESPONDER = ->(request) do
      [429, {"Content-Type" => "text/plain"}, ["Too many requests."]]
    end

    # @!visibility private
    DEFAULT_RATE_LIMITING_DISCRIMINATOR = ->(request) {
      request.actor ? "actor:#{request.actor.id}" : request.ip
    }
  end
end
