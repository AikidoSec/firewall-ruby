# frozen_string_literal: true

require "ffi"
require_relative "errors"

module Aikido::Zen
  module Internals
    extend FFI::Library

    def self.libzen_names
      lib_name = "libzen-v#{LIBZEN_VERSION}"
      lib_ext = FFI::Platform::LIBSUFFIX

      # Gem::Platform#version should be understood as an arbitrary Ruby defined
      # OS specific string. A platform with a version string is considered more
      # specific than a platform without a version string.
      # https://docs.ruby-lang.org/en/3.3/Gem/Platform.html

      platform = Gem::Platform.local.dup

      # Library names in preferred order.
      #
      # If two library names are added, the specific platform library names is
      # first and the generic platform library name is second.
      names = []

      names << "#{lib_name}-#{platform}.#{lib_ext}"

      unless platform.version.nil?
        platform.version = nil
        names << "#{lib_name}-#{platform}.#{lib_ext}"
      end

      names
    end

    # @return [String] the name of the extension we're loading, which we can
    # use in error messages.
    def self.libzen_name
      # The most generic platform library name.
      libzen_names.last
    end

    # Load the most specific library
    def self.load_libzen
      libzen_names.each do |name|
        path = File.expand_path(name, __dir__)
        begin
          return ffi_lib(path)
        rescue LoadError
          # empty
        end
      end
      raise LoadError, "Zen could not load its native extension #{libzen_name}"
    end

    begin
      load_libzen

      # @!method self.detect_sql_injection_native(query, input, dialect)
      # @param (see .detect_sql_injection)
      # @returns [Integer] 0 if no injection detected, 1 if an injection was
      #   detected, 2 if there was an internal error, or 3 if SQL tokenization failed.
      # @raise [Aikido::Zen::InternalsError] if there's a problem loading or
      #   calling libzen.
      attach_function :detect_sql_injection_native, :detect_sql_injection,
        [:pointer, :size_t, :pointer, :size_t, :int], :int
    rescue LoadError, FFI::NotFoundError => err # rubocop:disable Lint/ShadowedException
      # :nocov:

      # Emit an $stderr warning at startup.
      warn "Zen could not load its native extension #{libzen_name}: #{err}"

      def self.detect_sql_injection(query, *)
        attempt = format("%p for SQL injection", query)
        raise InternalsError.new(attempt, "loading", libzen_name)
      end

      # :nocov:
    else
      # Analyzes the SQL query to detect if the provided user input is being
      # passed as-is without escaping.
      #
      # @param query [String]
      # @param input [String]
      # @param dialect [Integer, #to_int] the SQL Dialect identifier in libzen.
      #   See {Aikido::Zen::Scanners::SQLInjectionScanner::DIALECTS}.
      #
      # @returns [Boolean]
      # @raise [Aikido::Zen::InternalsError] if there's a problem loading or
      #   calling libzen.
      def self.detect_sql_injection(query, input, dialect)
        query_bytes = encode_safely(query)
        input_bytes = encode_safely(input)

        query_ptr = FFI::MemoryPointer.new(:uint8, query_bytes.bytesize)
        input_ptr = FFI::MemoryPointer.new(:uint8, input_bytes.bytesize)

        query_ptr.put_bytes(0, query_bytes)
        input_ptr.put_bytes(0, input_bytes)

        case detect_sql_injection_native(query_ptr, query_bytes.bytesize, input_ptr, input_bytes.bytesize, dialect)
        when 0 then false
        when 1 then true
        when 2
          attempt = format("%s query %p with input %p", dialect, query, input)
          raise InternalsError.new(attempt, "calling detect_sql_injection in", libzen_name)
        when 3
          # SQL tokenization failed - return false (no injection detected)
          false
        end
      end
    end

    class << self
      private

      def encode_safely(string)
        string.encode("UTF-8", invalid: :replace, undef: :replace)
      end
    end
  end
end
