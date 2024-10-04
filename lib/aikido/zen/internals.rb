# frozen_string_literal: true

require "ffi"

module Aikido::Zen
  module Internals
    extend FFI::Library
    ffi_lib ["lib/aikido/zen/libzen", FFI::Platform::ARCH, FFI::Platform::LIBSUFFIX].join(".")

    # @!method self.detect_sql_injection(query, input, dialect)
    #
    # @param query [String]
    # @param input [String]
    # @param dialect [Integer, #to_int] the SQL Dialect identifier in libzen.
    #   See {Aikido::Zen::Scanners::SQLInjectionScanner::DIALECTS}.
    #
    # @returns [Boolean]
    attach_function :detect_sql_injection, [:string, :string, :int], :bool
  end
end
