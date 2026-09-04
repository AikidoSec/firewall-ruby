# frozen_string_literal: true

require_relative "ip_list/writer"
require_relative "ip_list/reader"
require_relative "address"

module Aikido::Zen
  class IPLists
    class IPList
      # @return [String, nil] opaque data
      attr_reader :data

      def initialize(ipv4_reader:, ipv6_reader:, data: nil)
        @data = data

        @readers = {ipv4: ipv4_reader, ipv6: ipv6_reader}
      end

      # @param ip [IPAddr, String, nil]
      # @return [Boolean]
      def include?(ip)
        address = Address.parse(ip)
        return false if address.nil?

        @readers.fetch(address.family).include?(address.to_i)
      end
    end
  end
end
