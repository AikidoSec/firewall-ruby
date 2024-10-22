# frozen_string_literal: true

module Aikido::Zen
  module Scanners
    # Inspects the result of DNS lookups, to determine if we're being the target
    # of a stored SSRF targeting IMDS addresses (169.254.169.254).
    class StoredSSRFScanner
      def self.call(hostname:, addresses:, operation:, sink:, context:, **opts)
        offending_address = new(hostname, addresses).attack?
        return if offending_address.nil?

        Attacks::StoredSSRFAttack.new(
          hostname: hostname,
          address: offending_address,
          sink: sink,
          context: context,
          operation: "#{sink.operation}.#{operation}"
        )
      end

      def initialize(hostname, addresses, config: Aikido::Zen.config)
        @hostname = hostname
        @addresses = addresses
        @config = config
      end

      # @return [String, nil] either the offending address, or +nil+ if no
      #   address is deemed dangerous.
      def attack?
        return false if @config.imds_allowed_hosts.include?(@hostname)

        @addresses.find do |candidate|
          DANGEROUS_ADDRESSES.any? { |address| address === candidate }
        end
      end

      DANGEROUS_ADDRESSES = [
        IPAddr.new("169.254.169.254"),
        IPAddr.new("fd00:ec2::254")
      ]
    end
  end
end
