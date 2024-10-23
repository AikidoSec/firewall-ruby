# frozen_string_literal: true

require "ffi"
require_relative "errors"

module Aikido::Zen
  module Internals
    extend FFI::Library

    lib_name = ["libzen", FFI::Platform::ARCH, FFI::Platform::LIBSUFFIX].join(".")
    begin
      ffi_lib File.expand_path(lib_name, __dir__)

      # @!method self.detect_sql_injection(query, input, dialect)
      #
      # @param query [String]
      # @param input [String]
      # @param dialect [Integer, #to_int] the SQL Dialect identifier in libzen.
      #   See {Aikido::Zen::Scanners::SQLInjectionScanner::DIALECTS}.
      #
      # @returns [Boolean]
      attach_function :detect_sql_injection, [:string, :string, :int], :bool
    rescue LoadError, FFI::NotFoundError => err
      # Emit an $stderr warning at startup.
      warn "Zen could not load its binary extension #{lib_name}: #{err}"

      def self.detect_sql_injection(query, *)
        raise InternalsMissingError.new(format("%p for SQL injection", query), lib_name)
      end
    end
  end
end
