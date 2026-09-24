# frozen_string_literal: true

require_relative "../format"

module Aikido::Zen
  class IPLists
    class IPList
      class Reader
        # @return [Integer] total size in bytes (count prefix + records)
        attr_reader :length

        def initialize(family:, io:, offset: 0)
          raise ArgumentError, "unknown family: #{family.inspect}" unless ADDRESS_SIZES.key?(family)

          @family = family
          @address_size = ADDRESS_SIZES.fetch(family)
          @record_size = @address_size * 2
          @io = io
          @offset = offset
          @count = 0

          read_count!
        end

        # @param ip [Integer] address in this reader's family
        # @return [Boolean]
        def include?(ip)
          return false if @count == 0

          index = bsearch_start_index(ip)
          return false if index.nil?

          ip <= read_ip(record_offset(index) + @address_size)
        end

        private

        def read_count!
          available = @io.size - @offset

          raise FormatError, "too small to contain a count" if available < COUNT_SIZE

          count = @io.pread(COUNT_SIZE, @offset).unpack1("Q>")

          @length = COUNT_SIZE + (count * @record_size)

          raise FormatError, "invalid IP list (expected #{@length} bytes, only #{available} available)" if @length > available

          @count = count
        end

        # Finds the index of the last record whose start ip is <= ip, or nil if ip
        # is before the first record's start.
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
          COUNT_SIZE + (index * @record_size)
        end

        def read_ip(offset)
          if @family == :ipv4
            read_ipv4(offset)
          else
            read_ipv6(offset)
          end
        end

        def read_ipv4(offset)
          @io.pread(4, @offset + offset).unpack1("N")
        end

        def read_ipv6(offset)
          hi, lo = @io.pread(16, @offset + offset).unpack("Q>Q>")
          (hi << 64) | lo
        end
      end
    end
  end
end
