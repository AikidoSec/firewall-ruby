# frozen_string_literal: true

require "ffi"

module Aikido::Zen
  module Internals
    extend FFI::Library
    ffi_lib "lib/aikido/zen/libzen." + FFI::Platform::LIBSUFFIX

    attach_function :detect_sql_injection, [:string, :string, :string], :boolean
  end
end
