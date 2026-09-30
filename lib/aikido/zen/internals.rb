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

      # @!method self.ip_matcher_create_native(networks_ptr, networks_len)
      # @param networks_ptr [FFI::Pointer] the networks, separated by newlines.
      # @param networks_len [Integer] the number of bytes in +networks_ptr+.
      # @return [FFI::Pointer] the matcher, or NULL if it could not be created.
      attach_function :ip_matcher_create_native, :ip_matcher_create, [:pointer, :size_t], :pointer, blocking: true

      # @!method self.ip_matcher_has_native(ip_matcher_handle_ptr, ip, ip_len)
      # @param ip_matcher_handle_ptr [FFI::Pointer]
      # @param ip [String]
      # @param ip_len [Integer] the number of bytes in +ip+.
      # @return [Integer] 0 if there is no match, 1 if there is a match, or 2
      #   if the lookup could not be processed.
      attach_function :ip_matcher_has_native, :ip_matcher_has, [:pointer, :buffer_in, :size_t], :int

      # @!method self.ip_matcher_memory_size_native(ip_matcher_handle_ptr)
      # @param ip_matcher_handle_ptr [FFI::Pointer]
      # @return [Integer] the number of bytes the matcher allocated.
      attach_function :ip_matcher_memory_size_native, :ip_matcher_memory_size, [:pointer], :size_t

      # @!method self.ip_matcher_rejected_count_native(ip_matcher_handle_ptr)
      # @param ip_matcher_handle_ptr [FFI::Pointer]
      # @return [Integer] how many networks were rejected when it was created.
      attach_function :ip_matcher_rejected_count_native, :ip_matcher_rejected_count, [:pointer], :size_t

      # @!method self.ip_matcher_free_native(ip_matcher_handle_ptr)
      # @param ip_matcher_handle_ptr [FFI::Pointer]
      # @return [void]
      attach_function :ip_matcher_free_native, :ip_matcher_free, [:pointer], :void
    rescue LoadError, FFI::NotFoundError => err # rubocop:disable Lint/ShadowedException
      # :nocov:

      # Emit an $stderr warning at startup.
      warn "Zen could not load its native extension #{libzen_name}: #{err}"

      def self.detect_sql_injection(query, *)
        attempt = format("scan %p for SQL injection", query)
        raise InternalsError.new(attempt, "loading", libzen_name)
      end

      def self.idor_analyze_sql(query, *)
        attempt = format("analyze SQL query %p", query)
        raise InternalsError.new(attempt, "loading", libzen_name)
      end

      def self.ip_matcher_create_native(*)
        raise InternalsError.new("create an IP matcher", "loading", libzen_name)
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
        query_bytes = Aikido::Zen::Helpers.encode_safely(query)
        input_bytes = Aikido::Zen::Helpers.encode_safely(input)

        query_ptr = FFI::MemoryPointer.new(:uint8, query_bytes.bytesize)
        input_ptr = FFI::MemoryPointer.new(:uint8, input_bytes.bytesize)

        query_ptr.put_bytes(0, query_bytes)
        input_ptr.put_bytes(0, input_bytes)

        result = detect_sql_injection_native(query_ptr, query_bytes.bytesize, input_ptr, input_bytes.bytesize, dialect)

        if result == 2
          attempt = format("scan %s query %p with input %p", dialect, query, input)
          raise InternalsError.new(attempt, "calling detect_sql_injection in", libzen_name)
        end

        result
      end

      def self.idor_analyze_sql(query, dialect)
        query_bytes = Aikido::Zen::Helpers.encode_safely(query)
        query_ptr = FFI::MemoryPointer.new(:uint8, query_bytes.bytesize)
        query_ptr.put_bytes(0, query_bytes)

        result_ptr = idor_analyze_sql_native(query_ptr, query_bytes.bytesize, dialect)
        result_json = result_ptr.read_string
        idor_free_string_native(result_ptr)

        JSON.parse(result_json)
      end
    end

    # Matches IP addresses against a set of networks, using libzen.
    class IPMatcher
      module RubyGC
        extend FFI::Library

        begin
          ffi_lib FFI::Library::CURRENT_PROCESS
          attach_function :adjust_memory_usage, :rb_gc_adjust_memory_usage, [:ssize_t], :void
        rescue LoadError # FFI::NotFoundError is a LoadError
          # :nocov:
          # The GC only uses this to account for native memory, so matching
          # keeps working without it.
          def self.adjust_memory_usage(_size)
          end
          # :nocov:
        end
      end
      private_constant :RubyGC

      class Handle < FFI::AutoPointer
        def initialize(ip_matcher_handle_ptr)
          super
          memory_size = Internals.ip_matcher_memory_size_native(ip_matcher_handle_ptr)
          RubyGC.adjust_memory_usage(memory_size)
        end

        def self.release(ip_matcher_handle_ptr)
          memory_size = Internals.ip_matcher_memory_size_native(ip_matcher_handle_ptr)
          Internals.ip_matcher_free_native(ip_matcher_handle_ptr)
          RubyGC.adjust_memory_usage(-memory_size)
        end
      end
      private_constant :Handle

      # @return [Integer] how many of the networks passed in were invalid,
      #   and are not included in the matcher.
      attr_reader :rejected_count

      # @param networks [Array<#to_s>] IP addresses or networks in CIDR notation.
      #   Invalid entries are not an error, see {#rejected_count}.
      def initialize(networks)
        networks = networks.map { |network| String(network) }
        @handle = Handle.new(create(networks))
        @rejected_count = Internals.ip_matcher_rejected_count_native(@handle)
      end

      # @param ip [String] an IP address.
      # @return [Boolean] whether the address is in any of the covered networks.
      def include?(ip)
        # Internals.ip_matcher_has returns 2 when the `ip` string is over 128
        # bytes or not UTF-8. Such `ip` strings cannot match, so are treated
        # as not included.
        Internals.ip_matcher_has_native(@handle, ip, ip.bytesize) == 1
      end

      private

      def create(networks)
        networks_string = networks.join("\n")
        networks_ptr = FFI::MemoryPointer.from_string(networks_string)

        ip_matcher_handle_ptr = Internals.ip_matcher_create_native(networks_ptr, networks_string.bytesize)

        if ip_matcher_handle_ptr.null?
          raise InternalsError.new("create an IP matcher", "calling ip_matcher_create in", Internals.libzen_name)
        end

        ip_matcher_handle_ptr
      end
    end
  end
end
