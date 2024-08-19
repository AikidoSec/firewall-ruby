# frozen_string_literal: true

require "delegate"
require "rack/request"
require_relative "payload"

module Aikido::Agent
  class Request < SimpleDelegator
    # @!visibility private
    RACK_REQUEST_BUILDER = ->(env) do
      Request.new(Rack::Request.new(env)) do |request|
        {
          query: request.GET,
          body: request.POST,
          route: {}
        }
      end
    end

    def self.from(env, config = Aikido::Agent.config)
      config.request_builder.call(env)
    end

    # @param [Rack::Request] a Request object that implements the
    #   Rack::Request API, to which we will delegate behavior.
    #
    # @yieldparam request [Rack::Request] the given request object.
    # @yieldreturn [Hash<Symbol, #flat_map>] map of payload source types
    #   to the actual data from the request to populate them.
    def initialize(delegate, &sources)
      super(delegate)
      @payload_sources = sources
    end

    # @return [Array<Aikido::Agent::Payload>] list of user inputs from all the
    #   different sources we recognize.
    def payloads
      @payloads ||= payload_sources.flat_map do |source, data|
        extract_payloads_from(data, source)
      end
    end

    def as_json
      {method: method}
    end

    # @!visibility private
    def payload_sources
      @payload_sources.call(self)
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
