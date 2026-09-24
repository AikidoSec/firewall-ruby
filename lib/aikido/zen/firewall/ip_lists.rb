# frozen_string_literal: true

require_relative "../ip_lists"
require_relative "ip_lists/ip_list"
require_relative "ip_lists/compiler"

module Aikido::Zen
  class Firewall
    class IPLists
      # @param path [String]
      # @param raw_ip_lists_data [Array<Hash>, nil]
      # @return [void]
      def self.write_from_json(path, raw_ip_lists_data)
        Aikido::Zen::IPLists.write(path, Compiler.compile(raw_ip_lists_data))
      end

      # @param path [String]
      # @raise [Errno::ENOENT] if `path` does not exist
      # @raise [Aikido::Zen::IPLists::FormatError] if `path` is not a valid IP lists file
      def initialize(path)
        @ip_lists = Aikido::Zen::IPLists.new(path)

        # When there is more than one IP list, the first IP list is the merged
        # IP list and acts as the fast path.
        @first_ip_list = @ip_lists.first

        @has_merged_ip_list = @ip_lists.size > 1

        @ip_list_cache = {}
      end

      def empty?
        @first_ip_list.nil?
      end

      def include?(ip)
        !empty? && @first_ip_list.include?(ip)
      end

      def matching_ip_lists(ip)
        return [] unless include?(ip)

        @ip_lists.filter_map.with_index do |ip_list, index|
          next if @has_merged_ip_list && index.zero?

          cached_ip_list(ip_list) if ip_list.include?(ip)
        end
      end

      def close
        @ip_lists.close
      end

      private

      def cached_ip_list(ip_list)
        @ip_list_cache[ip_list] ||= IPList.new(ip_list)
      end
    end
  end
end
