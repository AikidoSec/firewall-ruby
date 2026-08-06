# frozen_string_literal: true

require_relative "../format"

module Aikido::Zen
  module IPLists
    module Data
      class IPList
        # Binary-searches one family's IP range list serialized by `Writer`,
        # through a plain IO-like object's #pread -- this never opens or
        # owns a file itself.
        class Reader
          FormatError = Class.new(StandardError)

          # @param family [:ipv4, :ipv6]
          # @param io [#pread]
          # @param offset [Integer] absolute offset in +io+ where this IP
          #   list's data starts
          # @param length [Integer, nil] this IP list's size in bytes;
          #   defaults to everything from +offset+ to the end of +io+
          # @raise [FormatError] if the data at +offset+ doesn't look like a
          #   valid IP list for +family+
          def initialize(family:, io:, offset: 0, length: nil)
            raise ArgumentError, "unknown family: #{family.inspect}" unless FAMILY_CODES.key?(family)

            @family = family
            @record_size = RECORD_SIZES.fetch(family)
            @io = io
            @offset = offset
            @length = length || (io.size - offset)
            @count = 0

            parse_header!
          end

          # @param ip [Integer] the IP address to check, as an unsigned
          #   integer in the family this reader was configured for
          # @return [Boolean]
          def include?(ip)
            return false if @count == 0

            index = bsearch_start_index(ip)
            return false if index.nil?

            ip <= read_ip(record_offset(index) + (@record_size / 2))
          end

          private

          def parse_header!
            raise FormatError, "too small to contain a header" if @length < HEADER_SIZE

            magic, version, family_code, _reserved, count = @io.pread(HEADER_SIZE, @offset).unpack("a4CCnQ>")

            raise FormatError, "not an IP list" unless magic == MAGIC
            raise FormatError, "unsupported IP list format version #{version}" unless version == VERSION

            unless family_code == FAMILY_CODES.fetch(@family)
              raise FormatError, "expected #{@family} IP list, got family code #{family_code}"
            end

            expected_size = HEADER_SIZE + (count * @record_size)
            raise FormatError, "corrupt IP list (expected #{expected_size} bytes, got #{@length})" unless expected_size == @length

            @count = count
          end

          # Finds the index of the last record whose start ip is <= ip, or
          # nil if ip is before the first record's start.
          def bsearch_start_index(ip)
            low = 0
            high = @count - 1
            result = nil

            while low <= high
              mid = (low + high) / 2

              if read_ip(record_offset(mid)) <= ip
                result = mid
                low = mid + 1
              else
                high = mid - 1
              end
            end

            result
          end

          def record_offset(index)
            HEADER_SIZE + (index * @record_size)
          end

          def read_ip(offset)
            if @family == :ipv4
              @io.pread(4, @offset + offset).unpack1("N")
            else
              hi, lo = @io.pread(16, @offset + offset).unpack("Q>Q>")
              (hi << 64) | lo
            end
          end
        end
      end
    end
  end
end
