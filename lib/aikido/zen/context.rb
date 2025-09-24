# frozen_string_literal: true

require "forwardable"

require_relative "request"
require_relative "payload"

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

    # @param request [Rack::Request] a Request object that implements the
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
      @metadata = {}
      @scanning = false
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
      @payloads ||= payload_sources.flat_map do |source, data|
        extract_payloads_from(data, source)
      end
    end

    # @return [Boolean] whether attack protection for the currently requested
    #   endpoint was disabled on the Aikido dashboard, or if the source IP for
    #   this request is in the "Bypass List".
    def protection_disabled?
      return false if request.nil?

      !@settings.endpoints[request.route].protected? ||
        @settings.skip_protection_for_ips.include?(request.ip)
    end

    # @!visibility private
    def payload_sources
      @payload_sources.call(request)
    end

    private

    # @!visibility private
    def extract_payloads_from(data, source_type, prefix = nil)
      if data.respond_to?(:to_hash)
        data.to_hash.flat_map do |key, value|
          extract_payloads_from(value, source_type, [prefix, key].compact.join("."))
        end
      elsif data.respond_to?(:to_ary)
        array = data.to_ary
        return array if array.empty?

        payloads = array.flat_map.with_index do |value, index|
          extract_payloads_from(value, source_type, [prefix, index].compact.join("."))
        end

        # Special case for File.join given a possibly nested array of strings,
        # as might occur when a query parameter is an array.
        begin
          string = File.join__internal_for_aikido_zen(*array)
          if unsafe_path?(string)
            payloads << Payload.new(string, source_type, [prefix, "__File.join__"].compact.join("."))
          end
        rescue
          # Could not create special payload for File.join.
        end

        payloads
      else
        [Payload.new(data, source_type, prefix.to_s)]
      end
    end

    def unsafe_path?(filepath)
      normalized_filepath = Pathname.new(filepath).cleanpath.to_s.downcase

      Scanners::PathTraversal::DANGEROUS_PATH_PARTS.each do |dangerous_path_part|
        return true if normalized_filepath.include?(dangerous_path_part)
      end

      Scanners::PathTraversal::DANGEROUS_PATH_STARTS.each do |dangerous_path_start|
        return true if normalized_filepath.start_with?(dangerous_path_start)
      end

      false
    end
  end
end

require_relative "context/rack_request"
require_relative "context/rails_request"
