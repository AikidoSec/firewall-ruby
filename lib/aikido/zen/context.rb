# frozen_string_literal: true

require "rack/request"

require_relative "request"
require_relative "payload"

module Aikido::Zen
  class Context
    def self.from_rack_env(env, config = Aikido::Zen.config)
      config.request_builder.call(env)
    end

    attr_reader :request

    # @param [Rack::Request] a Request object that implements the
    #   Rack::Request API, to which we will delegate behavior.
    # @param settings [Aikido::Zen::RuntimeSettings]
    #
    # @yieldparam request [Rack::Request] the given request object.
    # @yieldreturn [Hash<Symbol, #flat_map>] map of payload source types
    #   to the actual data from the request to populate them.
    def initialize(request, settings: Aikido::Zen.runtime_settings, &sources)
      @request = request
      @settings = settings
      @payload_sources = sources
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
      @payloads ||= payload_sources.flat_map do |source, data|
        extract_payloads_from(data, source)
      end
    end

    # @return [Boolean] whether attack protection for the currently requested
    #   endpoint was disabled on the Aikido dashboard.
    def protection_disabled?
      return false if request.nil?

      !@settings.endpoints[request.route].protected?
    end

    # @!visibility private
    def payload_sources
      @payload_sources.call(request)
    end

    private

    def extract_payloads_from(data, source_type, prefix = nil)
      if data.respond_to?(:to_hash)
        data.to_hash.flat_map { |name, val|
          extract_payloads_from(val, source_type, [prefix, name].compact.join("."))
        }
      elsif data.respond_to?(:to_ary)
        data.to_ary.flat_map.with_index { |val, idx|
          extract_payloads_from(val, source_type, [prefix, idx].compact.join("."))
        }
      else
        Payload.new(data, source_type, prefix.to_s)
      end
    end
  end
end

require_relative "context/rack_request"
require_relative "context/rails_request"
