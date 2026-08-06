# frozen_string_literal: true

require_relative "../format"

module Aikido::Zen
  module IPLists
    module Data
      class IPList
        # Serializes one family's sorted integer IP ranges into the on-disk
        # binary format, through a plain IO-like object's #pwrite -- this
        # never opens or owns a file itself.
        #
        # File layout:
        #
        #   Header (16 bytes):
        #     0  4  Magic ("AKPL")
        #     4  1  Format version
        #     5  1  Address family (4 or 6)
        #     6  2  Reserved (zero)
        #     8  8  Record count (uint64 BE)
        #
        #   Records (sorted ascending by start, fixed width per family):
        #     ipv4:  4 bytes start + 4 bytes end (uint32 BE each)
        #     ipv6: 16 bytes start + 16 bytes end (uint128 BE each)
        class Writer
          UINT64_MASK = (1 << 64) - 1

          # @param family [:ipv4, :ipv6]
          def initialize(family:)
            raise ArgumentError, "unknown family: #{family.inspect}" unless FAMILY_CODES.key?(family)

            @family = family
          end

          # @param io [#pwrite]
          # @param ranges [Array<Range<Integer>>] in any order
          # @param offset [Integer] absolute offset in +io+ to start writing at
          # @return [io] the same io that was passed in
          def write(io, ranges, offset: 0)
            ranges = ranges.sort_by(&:begin)

            io.pwrite(header(ranges.size), offset)
            offset += HEADER_SIZE

            ranges.each do |range|
              bytes = write_range(range)
              io.pwrite(bytes, offset)
              offset += bytes.bytesize
            end

            io
          end

          private

          def header(count)
            [MAGIC, VERSION, FAMILY_CODES.fetch(@family), 0, count].pack("a4CCnQ>")
          end

          def write_range(range)
            write_ip(range.begin) + write_ip(range.end)
          end

          def write_ip(ip)
            if @family == :ipv4
              [ip].pack("N")
            else
              [(ip >> 64) & UINT64_MASK, ip & UINT64_MASK].pack("Q>Q>")
            end
          end
        end
      end
    end
  end
end
