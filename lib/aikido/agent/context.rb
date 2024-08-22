# frozen_string_literal: true

require "rack/request"

require_relative "request"
require_relative "payload"

module Aikido::Agent
  class Context
    def self.from_rack_env(env, config = Aikido::Agent.config)
      config.request_builder.call(env)
    end

    attr_reader :request

    # @param [Rack::Request] a Request object that implements the
    #   Rack::Request API, to which we will delegate behavior.
    #
    # @yieldparam request [Rack::Request] the given request object.
    # @yieldreturn [Hash<Symbol, #flat_map>] map of payload source types
    #   to the actual data from the request to populate them.
    def initialize(request, &sources)
      @request = request
      @payload_sources = sources
    end

    # Overrides the current request, and invalidates any memoized data obtained
    # from it. This is useful for scenarios where setting the request in the
    # middleware isn't enough, such as Rails, where the router modifies it after
    # the middleware has seen it.
    #
    # @param request [Rack::Request]
    # @return [void]
    def update_request(request)
      @payloads = nil
      @request = request
    end

    # @return [Array<Aikido::Agent::Payload>] list of user inputs from all the
    #   different sources we recognize.
    def payloads
      @payloads ||= payload_sources.flat_map do |source, data|
        extract_payloads_from(data, source)
      end
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
