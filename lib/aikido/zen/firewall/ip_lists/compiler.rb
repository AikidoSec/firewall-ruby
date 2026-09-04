# frozen_string_literal: true

require "ipaddr"
require "json"

module Aikido::Zen
  class Firewall
    class IPLists
      # Compiles raw IP lists for `Aikido::Zen::IPLists.write`, prepending a merged copy when there is more than one list.
      class Compiler
        class << self
          # @param raw_ip_lists_data [Array<Hash>, nil] raw IP lists from the API
          # @return [Array<Hash>] ip_lists_data ready for `IPLists.write`
          def compile(raw_ip_lists_data)
            ip_lists_data = Array(raw_ip_lists_data).map { |raw_ip_list_data| ip_list_data_for(raw_ip_list_data) }
            ip_lists_data.unshift(merged_ip_list_data(ip_lists_data)) if ip_lists_data.size > 1

            ip_lists_data
          end

          private

          # @param raw_ip_list_data [Hash] one raw IP list
          # @return [Hash] one entry of `ip_lists_data`
          def ip_list_data_for(raw_ip_list_data)
            ipv4_ranges, ipv6_ranges = ranges_for(raw_ip_list_data)
            data = JSON.generate(raw_ip_list_data.except("ips"))

            {ipv4_ranges: ipv4_ranges, ipv6_ranges: ipv6_ranges, data: data}
          end

          # @param ip_lists_data [Array<Hash>] entries from .ip_list_data_for
          # @return [Hash] the merged entry, with data set to nil
          def merged_ip_list_data(ip_lists_data)
            {
              ipv4_ranges: merge_ranges(ip_lists_data.flat_map { |data| data[:ipv4_ranges] }),
              ipv6_ranges: merge_ranges(ip_lists_data.flat_map { |data| data[:ipv6_ranges] }),
              data: nil
            }
          end

          # Parses ips into ipv4/ipv6 integer ranges.
          #
          # @param raw_ip_list_data [Hash] a raw JSON IP list
          # @return [(Array<Range<Integer>>, Array<Range<Integer>>)] ipv4, then ipv6 ranges
          # @raise [ArgumentError] if any address is not ipv4 or ipv6
          def ranges_for(raw_ip_list_data)
            ipv4_ranges = []
            ipv6_ranges = []

            Array(raw_ip_list_data["ips"]).each do |ip|
              address = IPAddr.new(ip)
              range = address.to_range
              ip_int_range = (range.begin.to_i..range.end.to_i)

              if address.ipv4?
                ipv4_ranges << ip_int_range
              elsif address.ipv6?
                ipv6_ranges << ip_int_range
              else
                raise ArgumentError, "unsupported IP address family: #{address.inspect}"
              end
            end

            [ipv4_ranges, ipv6_ranges]
          end

          def merge_ranges(ranges)
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
        end
      end
    end
  end
end
