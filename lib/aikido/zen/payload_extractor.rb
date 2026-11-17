# frozen_string_literal: true

module Aikido::Zen
  class PayloadExtractor
    # @param config [Aikido::Zen::Config]
    def initialize(config: Aikido::Zen.config)
      @max_depth = config.extract_payloads_max_depth
      @max_url_decoded_variants = config.extract_payloads_max_url_decoded_variants
    end

    # Yields each user input in the data of a payload source of the request.
    #
    # @param data [Object] the data of the payload source.
    # @param path [Path] the path to the data, which is the root by default.
    # @yieldparam value [String] the input, as a valid UTF-8 string.
    # @yieldparam path [Path] the path to the input. The path is reused, so the
    #   block must not keep it.
    # @return [void]
    def extract(data, path = Path.new, &block)
      return if path.size > @max_depth

      case data
      when String
        extract_string(data, path, &block)
      when Hash
        extract_hash(data, path, &block)
      when Array
        extract_array(data, path, &block)
      else
        if data.respond_to?(:to_hash)
          extract_hash(data.to_hash, path, &block)
        elsif data.respond_to?(:to_ary)
          extract_array(data.to_ary, path, &block)
        end
      end
    end

    private

    def extract_string(string, path, &block)
      jwt_payload = nil

      [string, *url_decoded_variants(string)].each do |value|
        yield value_for(value), path

        jwt_payload ||= Helpers.decode_jwt_payload(value)
      end

      if jwt_payload
        path.push(Path::JWT_MARKER)
        extract(jwt_payload, path, &block)
        path.pop
      end
    end

    def extract_hash(hash, path, &block)
      hash.each_pair do |key, value|
        path.push(key)

        yield value_for(key), path

        extract(value, path, &block)
        path.pop
      end
    end

    def extract_array(array, path, &block)
      return if array.empty?

      array.each_with_index do |value, index|
        path.push(index)
        extract(value, path, &block)
        path.pop
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
              path.push(Path::FILE_JOIN_MARKER)
              yield value_for(string), path
              path.pop
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

require_relative "payload_extractor/path"
