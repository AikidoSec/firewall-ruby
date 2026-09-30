# frozen_string_literal: true

require "ffi"
require_relative "errors"

module Aikido::Zen
  module Internals
    extend FFI::Library

    @ip_matcher_available = false

    def self.ip_matcher_available?
      @ip_matcher_available
    end

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

      # :nocov:
      unless platform.version.nil?
        platform.version = nil
        names << "#{lib_name}-#{platform}.#{lib_ext}"
      end
      # :nocov:

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
      # :nocov:
      raise LoadError, "Zen could not load its native extension #{libzen_name}"
      # :nocov:
    end

    begin
      load_libzen

      # @!method self.detect_sql_injection_native(query, input, dialect)
      # @param (see .detect_sql_injection)
      # @return [Integer] 0 if no injection detected, 1 if an injection was
      #   detected, 2 if there was an internal error, or 3 if SQL tokenization failed.
      # @raise [Aikido::Zen::InternalsError] if there's a problem loading or
      #   calling libzen.
      attach_function :detect_sql_injection_native, :detect_sql_injection,
        [:pointer, :size_t, :pointer, :size_t, :int], :int

      attach_function :idor_analyze_sql_native, :idor_analyze_sql_ffi, [:pointer, :size_t, :int], :pointer

      attach_function :idor_free_string_native, :free_string, [:pointer], :void

      attach_function :ip_matcher_create_native, :ip_matcher_create, [:pointer, :size_t], :pointer, blocking: true
      attach_function :ip_matcher_has_native, :ip_matcher_has, [:pointer, :buffer_in, :size_t], :int
      attach_function :ip_matcher_memory_size_native, :ip_matcher_memory_size, [:pointer], :size_t
      attach_function :ip_matcher_free_native, :ip_matcher_free, [:pointer], :void
      @ip_matcher_available = true
    rescue LoadError, FFI::NotFoundError => err # rubocop:disable Lint/ShadowedException
      # :nocov:

      # Emit an $stderr warning at startup.
      warn "Zen could not load its native extension #{libzen_name}: #{err}"

      def self.detect_sql_injection(query, *)
        attempt = format("%p for SQL injection", query)
        raise InternalsError.new(attempt, "loading", libzen_name)
      end

      def self.idor_analyze_sql(query, *)
        attempt = format("%p for SQL analysis", query)
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
      # @return [Boolean]
      # @raise [Aikido::Zen::InternalsError] if there's a problem loading or
      #   calling libzen.
      def self.detect_sql_injection(query, input, dialect)
        query_bytes = encode_safely(query)
        input_bytes = encode_safely(input)

        query_ptr = FFI::MemoryPointer.new(:uint8, query_bytes.bytesize)
        input_ptr = FFI::MemoryPointer.new(:uint8, input_bytes.bytesize)

        query_ptr.put_bytes(0, query_bytes)
        input_ptr.put_bytes(0, input_bytes)

        result = detect_sql_injection_native(query_ptr, query_bytes.bytesize, input_ptr, input_bytes.bytesize, dialect)

        if result == 2
          attempt = format("%s query %p with input %p", dialect, query, input)
          raise InternalsError.new(attempt, "calling detect_sql_injection in", libzen_name)
        end

        result
      end

      def self.idor_analyze_sql(query, dialect)
        query_bytes = encode_safely(query)
        query_ptr = FFI::MemoryPointer.new(:uint8, query_bytes.bytesize)
        query_ptr.put_bytes(0, query_bytes)

        result_ptr = idor_analyze_sql_native(query_ptr, query_bytes.bytesize, dialect)
        result_json = result_ptr.read_string
        idor_free_string_native(result_ptr)

        JSON.parse(result_json)
      end
    end

    class IPMatcher
      module RubyGC
        extend FFI::Library
        ffi_lib FFI::Library::CURRENT_PROCESS
        attach_function :adjust_memory_usage, :rb_gc_adjust_memory_usage, [:ssize_t], :void
      end
      private_constant :RubyGC

      class Input < FFI::Struct
        layout :data, :pointer,
          :length, :size_t
      end
      private_constant :Input

      class Handle < FFI::AutoPointer
        def initialize(pointer)
          super
          RubyGC.adjust_memory_usage(Internals.ip_matcher_memory_size_native(pointer))
        end

        def self.release(pointer)
          memory_size = Internals.ip_matcher_memory_size_native(pointer)
          Internals.ip_matcher_free_native(pointer)
          RubyGC.adjust_memory_usage(-memory_size)
        end
      end
      private_constant :Handle

      def initialize(networks)
        @handle = Handle.new(create(networks.map { |network| String(network) }))
      end

      def include?(network)
        Internals.ip_matcher_has_native(@handle, network, network.bytesize) == 1
      end

      private

      def create(networks)
        network_buffer = FFI::MemoryPointer.from_string(networks.join)
        unless networks.empty?
          descriptor_buffer = FFI::MemoryPointer.new(Input, networks.length)
          network_offset = 0

          networks.each_with_index do |network, index|
            descriptor_offset = Input.size * index
            descriptor_buffer.put_pointer(descriptor_offset + Input.offset_of(:data), network_buffer + network_offset)
            descriptor_buffer.put(:size_t, descriptor_offset + Input.offset_of(:length), network.bytesize)
            network_offset += network.bytesize
          end
        end

        handle = Internals.ip_matcher_create_native(descriptor_buffer || FFI::Pointer::NULL, networks.length)
        if handle.null?
          raise InternalsError.new("an IP matcher", "calling ip_matcher_create in", Internals.libzen_name)
        end

        handle
      ensure
        descriptor_buffer&.free
        network_buffer&.free
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
