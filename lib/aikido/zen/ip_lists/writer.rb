# frozen_string_literal: true

require_relative "ip_list/writer"
require_relative "format"

module Aikido::Zen
  class IPLists
    # Writes an IP lists file with:
    #
    # - 32-bit magic ("IPLS") + 8-bit version header
    # - zero or more IP list objects:
    #   - 64-bit count * 2 * 32-bit IPv4 address (range start and end)
    #   - 64-bit count * 2 * 128-bit IPv6 address (range start and end)
    #   - 64-bit count * bytes of opaque data
    #
    # The IP lists file is written atomically; the IP lists are written to a
    # temporary path then moved into place.
    class Writer
      # @param path [String]
      def initialize(path)
        @path = path
      end

      # @param ip_lists_data [Array<Hash>] each ip list data with :ipv4_ranges, :ipv6_ranges and :data
      # @return [void]
      def write(ip_lists_data)
        tmp_path = "#{@path}.tmp"

        File.open(tmp_path, "wb") do |file|
          offset = write_file_header(file)

          ip_lists_data.each do |ip_list_data|
            offset = write_ip_list(file, offset, ip_list_data)
          end
        end

        File.rename(tmp_path, @path)
      end

      private

      def write_file_header(file)
        file.pwrite([MAGIC, VERSION].pack("a4C"), 0)

        FILE_HEADER_SIZE
      end

      def write_ip_list(file, offset, ip_list_data)
        offset = write_ranges(file, offset, :ipv4, ip_list_data[:ipv4_ranges])
        offset = write_ranges(file, offset, :ipv6, ip_list_data[:ipv6_ranges])
        write_data(file, offset, ip_list_data[:data])
      end

      def write_ranges(file, offset, family, ranges)
        ranges = Array(ranges)

        IPList::Writer.new(family: family).write(file, ranges, offset: offset)

        offset + COUNT_SIZE + (ranges.size * ADDRESS_SIZES.fetch(family) * 2)
      end

      def write_data(file, offset, data)
        bytes = data.to_s

        file.pwrite([bytes.bytesize].pack("Q>"), offset)
        offset += COUNT_SIZE

        file.pwrite(bytes, offset)
        offset + bytes.bytesize
      end
    end
  end
end
