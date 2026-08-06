# frozen_string_literal: true

require "json"

require_relative "ip_list/writer"
require_relative "format"

module Aikido::Zen
  module IPLists
    module Data
      # Writes a `Data` file: many IP lists packed into one physical file,
      # instead of one file pair per list.
      #
      # A merged, coalesced (overlaps combined) copy of every IP list's
      # ranges is written per family too, for the common case: a fast
      # #include? that doesn't care which IP list an address came from.
      # Every original IP list is still written in full alongside it, used
      # only as a fallback for exact attribution -- see `Data::Reader`.
      #
      # Writes atomically (to a temp path in the same directory, then
      # renames it over +path+), so a `Data::Reader` in another process --
      # e.g. a preforked worker sharing this file with the process writing
      # it -- never sees a partially-written file.
      #
      # File layout:
      #   4 bytes:  table of contents length (uint32 BE)
      #   N bytes:  table of contents, JSON (tiny -- one entry per IP list,
      #             loaded whole, no need for binary search over it)
      #   ...:      merged ipv4 data, then merged ipv6 data
      #   ...:      IP list 0's ipv4 data, then its ipv6 data
      #   ...:      IP list 1's ipv4 data, then its ipv6 data
      #   ...
      class Writer
        TOC_LENGTH_SIZE = 4

        # @param path [String]
        # @param ip_lists [Array<#key, #description, #ipv4_ranges, #ipv6_ranges>]
        def self.write(path, ip_lists)
          merged_ipv4 = merge_ranges(ip_lists.flat_map(&:ipv4_ranges))
          merged_ipv6 = merge_ranges(ip_lists.flat_map(&:ipv6_ranges))

          offset = 0
          merged_toc, offset = ip_list_toc_entry(offset, ipv4_count: merged_ipv4.size, ipv6_count: merged_ipv6.size)

          ip_lists_toc = ip_lists.map do |ip_list|
            toc, offset = ip_list_toc_entry(offset, ipv4_count: ip_list.ipv4_ranges.size, ipv6_count: ip_list.ipv6_ranges.size)
            toc[:key] = ip_list.key
            toc[:description] = ip_list.description
            toc
          end

          toc_json = JSON.generate(merged: merged_toc, ip_lists: ip_lists_toc)
          data_start = TOC_LENGTH_SIZE + toc_json.bytesize

          tmp_path = "#{path}.tmp"

          File.open(tmp_path, "wb") do |file|
            file.seek(0)
            file.write([toc_json.bytesize].pack("N"))
            file.write(toc_json)

            write_ip_list(file, data_start, merged_toc, :ipv4, merged_ipv4)
            write_ip_list(file, data_start, merged_toc, :ipv6, merged_ipv6)

            ip_lists.zip(ip_lists_toc).each do |ip_list, toc|
              write_ip_list(file, data_start, toc, :ipv4, ip_list.ipv4_ranges)
              write_ip_list(file, data_start, toc, :ipv6, ip_list.ipv6_ranges)
            end
          end

          File.rename(tmp_path, path)
        end

        def self.write_ip_list(file, data_start, toc, family, ranges)
          offset = data_start + toc.fetch(:"#{family}_offset")
          IPList::Writer.new(family: family).write(file, ranges, offset: offset)
        end
        private_class_method :write_ip_list

        def self.ip_list_toc_entry(offset, ipv4_count:, ipv6_count:)
          ipv4_length = HEADER_SIZE + (ipv4_count * RECORD_SIZES.fetch(:ipv4))
          ipv6_length = HEADER_SIZE + (ipv6_count * RECORD_SIZES.fetch(:ipv6))

          toc = {ipv4_offset: offset, ipv4_length: ipv4_length}
          offset += ipv4_length
          toc[:ipv6_offset] = offset
          toc[:ipv6_length] = ipv6_length
          offset += ipv6_length

          [toc, offset]
        end
        private_class_method :ip_list_toc_entry

        # Coalesces overlapping/adjacent ranges. Only safe where exact
        # attribution isn't needed afterwards -- the merged copy is the
        # fast path; `Data::Reader`'s fallback re-checks the original IP
        # lists for that.
        def self.merge_ranges(ranges)
          sorted = ranges.sort_by(&:begin)
          merged = []

          sorted.each do |range|
            if merged.any? && range.begin <= merged.last.end + 1
              previous = merged.pop
              merged << (previous.begin..[previous.end, range.end].max)
            else
              merged << range
            end
          end

          merged
        end
        private_class_method :merge_ranges
      end
    end
  end
end
