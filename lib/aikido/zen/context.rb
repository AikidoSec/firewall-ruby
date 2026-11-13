# frozen_string_literal: true

require "forwardable"
require "set"

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

      @max_depth = @config.extract_payloads_max_depth
      @max_url_decoded_variants = @config.extract_payloads_max_url_decoded_variants

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

    # @return [Set<String>] unique user inputs from all the
    #   different sources we recognize.
    def payloads
      return @payloads if @payloads

      results = Set.new
      payload_sources.each_value do |data|
        extract_payloads_from(data, results)
      end
      @payloads = results
    end

    def query_payloads
      results = Set.new
      extract_payloads_from(payload_sources[:query], results)
      results
    end

    def payload_for(value)
      payload_sources.each do |source, data|
        payload = find_payload(value, data, source)
        return payload if payload
      end
      Payload.new(value, "unknown", "unknown")
    rescue
      Payload.new(value, "unknown", "unknown")
    end

    # @!visibility private
    def payload_sources
      @payload_sources.call(request)
    end

    private

    # Applications may decode input again, so a value can reach a sink as
    # any of its successive URL-decoded variants.
    #
    # @param string [String] the string.
    # @return [Array<String>] the successive URL-decoded variants of string.
    def url_decoded_variants(string)
      variants = []

      current = string

      @max_url_decoded_variants.times do
        current = Helpers.url_decode(current)
        break unless current

        variants << current
      end

      variants
    end

    # @!visibility private
    def extract_payloads_from(data, results, depth = 0)
      return if depth > @max_depth

      if data.is_a?(String)
        jwt_payload = nil

        [data, *url_decoded_variants(data)].each do |value|
          results.add(value)
          jwt_payload ||= Helpers.decode_jwt_payload(value)
        end

        extract_payloads_from(jwt_payload, results, depth + 1) if jwt_payload
      elsif data.respond_to?(:to_hash)
        hash = data.is_a?(Hash) ? data : data.to_hash
        hash.each_pair do |key, value|
          results.add(key.to_s)
          extract_payloads_from(value, results, depth + 1)
        end
      elsif data.respond_to?(:to_ary)
        array = data.to_ary
        return if array.empty?

        array.each do |value|
          extract_payloads_from(value, results, depth + 1)
        end

        unless Aikido::Zen.config.harden?
          # Special case for File.join given a possibly nested array of strings,
          # as might occur when a query parameter is an array.

          # File.join recursively joins nested string arrays, and can overflow
          # the stack given deeply nested arrays.
          #
          # Flatten array to max depth and check that the flattened array is an
          # array of strings before calling File.join__internal_for_aikido_zen,
          # only if the array was fully flattened, to prevent a stack overflow.
          #
          # Checking that all values are Strings handily prevents a TypeError
          # from being raised.
          flattened_array = array.flatten(@max_depth)
          if flattened_array.all? { |string| string.is_a?(String) }
            begin
              string = File.join__internal_for_aikido_zen(*flattened_array)
              if unsafe_path?(string)
                results.add(string)
              end
            rescue
              # Could not create special payload for File.join.
            end
          end
        end
      end
    end

    # @!visibility private
    def find_payload(target, data, source, prefix = nil, depth = 0)
      return if depth > @max_depth

      if data.is_a?(String)
        jwt_payload = nil
        [data, *url_decoded_variants(data)].each do |value|
          return Payload.new(value, source, prefix.to_s) if value == target
          jwt_payload ||= Helpers.decode_jwt_payload(value)
        end
        return find_payload(target, jwt_payload, source, "#{prefix}<jwt>", depth + 1) if jwt_payload
      elsif data.respond_to?(:to_hash)
        hash = data.is_a?(Hash) ? data : data.to_hash
        hash.each_pair do |key, value|
          path = [prefix, key].compact.join(".")
          return Payload.new(key.to_s, source, path) if key.to_s == target
          payload = find_payload(target, value, source, path, depth + 1)
          return payload if payload
        end
      elsif data.respond_to?(:to_ary)
        array = data.to_ary
        array.each_with_index do |value, index|
          path = [prefix, index].compact.join(".")
          payload = find_payload(target, value, source, path, depth + 1)
          return payload if payload
        end

        unless Aikido::Zen.config.harden?
          # Special case for File.join given a possibly nested array of strings,
          # as might occur when a query parameter is an array.

          # File.join recursively joins nested string arrays, and can overflow
          # the stack given deeply nested arrays.
          #
          # Flatten array to max depth and check that the flattened array is an
          # array of strings before calling File.join__internal_for_aikido_zen,
          # only if the array was fully flattened, to prevent a stack overflow.
          #
          # Checking that all values are Strings handily prevents a TypeError
          # from being raised.
          flattened_array = array.flatten(@max_depth)
          if flattened_array.all? { |string| string.is_a?(String) }
            string = begin
              File.join__internal_for_aikido_zen(*flattened_array)
            rescue
              # Could not create special payload for File.join.
              nil
            end
            return Payload.new(string, source, "#{prefix}<File.join>") if string && string == target && unsafe_path?(string)
          end
        end
      end
      nil
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
