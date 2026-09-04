# frozen_string_literal: true

require_relative "ip_list/reader"
require_relative "ip_list"

module Aikido::Zen
  class IPLists
    # Reads an IP lists file. See {Aikido::Zen::IPLists::Writer}.
    class Reader
      # @return [Array<IPList>]
      attr_reader :ip_lists

      # @param path [String]
      # @raise [Errno::ENOENT] if `path` does not exist
      # @raise [Aikido::Zen::IPLists::FormatError] if `path` is not a valid IP lists file
      def initialize(path)
        @file = File.open(path, "rb")

        read_file_header

        @ip_lists = read_ip_lists
      end

      def close
        @file.close
      end

      private

      def read_file_header
        raise FormatError, "too small to contain a header" if @file.size < FILE_HEADER_SIZE

        magic, version = @file.pread(FILE_HEADER_SIZE, 0).unpack("a4C")

        raise FormatError, "not an IP lists file" unless magic == MAGIC
        raise FormatError, "unsupported IP lists format version #{version}" unless version == VERSION
      end

      def read_ip_lists
        ip_lists = []

        offset = FILE_HEADER_SIZE
        size = @file.size

        while offset < size
          ipv4_reader = IPList::Reader.new(family: :ipv4, io: @file, offset: offset)
          offset += ipv4_reader.length

          ipv6_reader = IPList::Reader.new(family: :ipv6, io: @file, offset: offset)
          offset += ipv6_reader.length

          data, offset = read_data(offset)

          ip_lists << IPList.new(ipv4_reader: ipv4_reader, ipv6_reader: ipv6_reader, data: data)
        end

        ip_lists
      end

      def read_data(offset)
        length = @file.pread(COUNT_SIZE, offset).unpack1("Q>")
        offset += COUNT_SIZE

        data = length.zero? ? "" : @file.pread(length, offset)
        [data, offset + length]
      end
    end
  end
end
