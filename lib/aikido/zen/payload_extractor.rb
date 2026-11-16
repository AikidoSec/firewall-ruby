# frozen_string_literal: true

require_relative "payload"

module Aikido::Zen
  # Extracts the user inputs from the sources of a request into Payloads.
  class PayloadExtractor
    # @param config [Aikido::Zen::Config]
    def initialize(config: Aikido::Zen.config)
      @max_depth = config.extract_payloads_max_depth
      @max_url_decoded_variants = config.extract_payloads_max_url_decoded_variants
    end

    # @param sources [Hash<Symbol, Object>] map of payload source types to
    #   the actual data from the request to populate them.
    # @return [Array<Aikido::Zen::Payload>] list of user inputs from all the
    #   sources.
    def extract(sources)
      @payloads = []

      sources.each do |source, data|
        extract_payloads_from(data, source)
      end

      @payloads
    end

    private

    # @!visibility private
    def extract_payloads_from(data, source_type, prefix = "", depth = 0)
      return if depth > @max_depth

      case data
      when String
        extract_string(data, source_type, prefix, depth)
      when Hash
        extract_hash(data, source_type, prefix, depth)
      when Array
        extract_array(data, source_type, prefix, depth)
      else
        if data.respond_to?(:to_hash)
          extract_hash(data.to_hash, source_type, prefix, depth)
        elsif data.respond_to?(:to_ary)
          extract_array(data.to_ary, source_type, prefix, depth)
        end
      end
    end

    def extract_string(string, source_type, prefix, depth)
      jwt_payload = nil

      [string, *url_decoded_variants(string)].each do |value|
        @payloads << Payload.new(value_for(value), source_type, prefix)

        jwt_payload ||= Helpers.decode_jwt_payload(value)
      end

      if jwt_payload
        extract_payloads_from(jwt_payload, source_type, "#{prefix}<jwt>", depth + 1)
      end
    end

    def extract_hash(hash, source_type, prefix, depth)
      hash.each_pair do |key, value|
        path = path_for(prefix, key, depth)

        @payloads << Payload.new(value_for(key), source_type, path)

        extract_payloads_from(value, source_type, path, depth + 1)
      end
    end

    def extract_array(array, source_type, prefix, depth)
      return if array.empty?

      array.each_with_index do |value, index|
        extract_payloads_from(value, source_type, path_for(prefix, index, depth), depth + 1)
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
              @payloads << Payload.new(value_for(string), source_type, "#{prefix}<File.join>")
            end
          rescue
            # Could not create special payload for File.join.
          end
        end
      end
    end

    # @param value [Object] the value.
    # @return [String] the value, as a valid UTF-8 string.
    def value_for(value)
      Helpers.encode_safely(value.to_s)
    end

    # @param prefix [String] the path of the hash or array.
    # @param segment [Object] the key or index.
    # @param depth [Integer] the depth of the hash or array.
    # @return [String] the path, as a valid UTF-8 string.
    def path_for(prefix, segment, depth)
      separator = "." unless depth.zero?

      segment = Helpers.encode_safely(segment.to_s) unless segment.is_a?(Integer)

      "#{prefix}#{separator}#{segment}"
    end

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
