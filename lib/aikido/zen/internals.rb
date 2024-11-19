# frozen_string_literal: true

require "ffi"
require_relative "errors"

module Aikido::Zen
  module Internals
    extend FFI::Library

    class << self
      # @return [String] the name of the extension we're loading, which we can
      #   use in error messages to identify the architecture.
      attr_accessor :libzen_name
    end

    self.libzen_name = [
      "libzen-v#{LIBZEN_VERSION}",
      FFI::Platform::ARCH,
      FFI::Platform::LIBSUFFIX
    ].join(".")

    begin
      ffi_lib File.expand_path(libzen_name, __dir__)

      # @!method self.detect_sql_injection_native(query, input, dialect)
      # @param (see .detect_sql_injection)
      # @returns [Integer] 0 if no injection detected, 1 if an injection was
      #   detected, or 2 if there was an internal error.
      # @raise [Aikido::Zen::InternalsError] if there's a problem loading or
      #   calling libzen.
      attach_function :detect_sql_injection_native, :detect_sql_injection,
        [:string, :string, :int], :int
    rescue LoadError, FFI::NotFoundError => err
      # :nocov:

      # Emit an $stderr warning at startup.
      warn "Zen could not load its binary extension #{libzen_name}: #{err}"

      def self.detect_sql_injection(query, *)
        attempt = format("%p for SQL injection", query)
        raise InternalsError.new(attempt, "loading", Internals.libzen_name)
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
        case detect_sql_injection_native(query, input, dialect)
        when 0 then false
        when 1 then true
        when 2
          attempt = format("%s query %p with input %p", dialect, query, input)
          raise InternalsError.new(attempt, "calling detect_sql_injection in", libzen_name)
        end
      end
    end
  end
end
