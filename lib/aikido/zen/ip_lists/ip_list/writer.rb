# frozen_string_literal: true

require_relative "../format"

module Aikido::Zen
  class IPLists
    class IPList
      # Writes an IP list. See {Aikido::Zen::IPLists::Writer}.
      class Writer
        UINT64_MASK = (1 << 64) - 1

        def initialize(family:)
          raise ArgumentError, "unknown family: #{family.inspect}" unless ADDRESS_SIZES.key?(family)

          @family = family
        end

        # @param io [#pwrite]
        # @param ranges [Array<Range<Integer>>] the IP ranges in any order in this writers family
        # @param offset [Integer] the absolute offset in `io` to start writing at
        # @return [#pwrite] the `io` object
        def write(io, ranges, offset: 0)
          ranges = ranges.sort_by(&:begin)

          io.pwrite([ranges.size].pack("Q>"), offset)
          offset += COUNT_SIZE

          ranges.each do |range|
            bytes = write_range(range)
            io.pwrite(bytes, offset)
            offset += bytes.bytesize
          end

          io
        end

        private

        def write_range(range)
          if @family == :ipv4
            write_ipv4(range.begin) + write_ipv4(range.end)
          else
            write_ipv6(range.begin) + write_ipv6(range.end)
          end
        end

        def write_ipv4(ip)
          [ip].pack("N")
        end

        def write_ipv6(ip)
          [(ip >> 64) & UINT64_MASK, ip & UINT64_MASK].pack("Q>Q>")
        end
      end
    end
  end
end
