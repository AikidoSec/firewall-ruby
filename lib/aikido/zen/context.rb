# frozen_string_literal: true

require "forwardable"

require_relative "request"
require_relative "payload_extractor"

module Aikido::Zen
  class Context
    # Build a Context object for the current HTTP request based on the currently
    # configured request builder.
    #
    # @param env [Hash] the Rack env hash.
    # @param config [Aikido::Zen::Config]
    # @return [Aikido::Zen::Context]
    def self.from_rack_env(env, config = Aikido::Zen.config)
      config.request_builder.call(env)
    end

    # @return [Aikido::Zen::Request]
    attr_reader :request

    # @return [Boolean]
    attr_accessor :scanning
    alias_method :scanning?, :scanning

    # @return [Boolean, nil] whether the request is bypassed.
    attr_accessor :request_bypassed
    alias_method :request_bypassed?, :request_bypassed

    # @return [Boolean] whether attack protection for the currently requested
    #   endpoint was disabled on the Aikido dashboard, or if the source IP for
    #   this request is in the "Bypass List".
    attr_accessor :protection_disabled
    alias_method :protection_disabled?, :protection_disabled

    # @return [Boolean]
    attr_accessor :idor_protection_enabled
    alias_method :idor_protection_enabled?, :idor_protection_enabled

    # @return [Integer]
    attr_accessor :custom_events

    # @param request [Rack::Request] a Request object that implements the
    #   Rack::Request API, to which we will delegate behavior.
    # @param settings [Aikido::Zen::RuntimeSettings]
    #
    # @yieldparam request [Rack::Request] the given request object.
    # @yieldreturn [Hash<Symbol, #flat_map>] map of payload source types
    #   to the actual data from the request to populate them.
    def initialize(request, zen: Aikido::Zen, config: zen.config, settings: zen.runtime_settings, &sources)
      @request = request
      @config = config
      @settings = settings
      @payload_sources = sources
      @payload_extractor = PayloadExtractor.new(config: @config)

      @metadata = {}
      @scanning = false
      @request_bypassed = nil
      @protection_disabled = false
      @idor_protection_enabled = false
      @custom_events = 0
    end

    # Fetch some metadata stored in the Context.
    #
    # @param key [String]
    # @return [Object, nil]
    def [](key)
      @metadata[key]
    end

    # Store some metadata in the Context so other Scanners can use it.
    #
    # @param key [String]
    # @param value [Object]
    # @return [void]
    def []=(key, value)
      @metadata[key] = value
    end

    # Overrides the current request, and invalidates any memoized data obtained
    # from it. This is useful for scenarios where setting the request in the
    # middleware isn't enough, such as Rails, where the router modifies it after
    # the middleware has seen it.
    #
    # @param new_request [Rack::Request]
    # @return [void]
    def update_request(new_request)
      @payloads = nil
      request.__setobj__(new_request)
    end

    # @return [Array<Aikido::Zen::Payload>] list of user inputs from all the
    #   different sources we recognize.
    def payloads
      @payloads ||= @payload_extractor.extract(payload_sources)
    end

    # @!visibility private
    def payload_sources
      @payload_sources.call(request)
    end
  end
end

require_relative "context/rack_request"
require_relative "context/rails_request"
