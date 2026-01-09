# frozen_string_literal: true

module Aikido::Zen
  module Scanners
    # Inspects the result of DNS lookups, to determine if we're being the target
    # of a stored SSRF targeting IMDS addresses (169.254.169.254).
    class StoredSSRFScanner
      # Stored-SSRF can occur without external input, so we do not require a
      # context to determine if an attack is happening.
      def self.skips_on_nil_context?
        false
      end

      def self.call(hostname:, addresses:, operation:, sink:, context:, **opts)
        offending_address = new(hostname, addresses).attack?
        return if offending_address.nil?

        Attacks::StoredSSRFAttack.new(
          hostname: hostname,
          address: offending_address,
          sink: sink,
          context: context,
          operation: "#{sink.operation}.#{operation}",
          stack: Aikido::Zen.clean_stack_trace
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
        return unless @config.stored_ssrf? # Feature flag

        return if @config.imds_allowed_hosts.include?(@hostname)

        @addresses.find do |address|
          DANGEROUS_ADDRESSES.any? do |dangerous_address|
            # Addresses are not considered stored IMDS addresses if the address
            # is the same as the hostname.
            next if address == @hostname

            # True if the dangerous address is address or includes the address.
            dangerous_address === address
          end
        end
      end

      # A dangerous address may be an individual address or an address range.
      DANGEROUS_ADDRESSES = [
        IPAddr.new("169.254.169.254"),
        IPAddr.new("100.100.100.200"),
        IPAddr.new("::ffff:169.254.169.254"),
        IPAddr.new("::ffff:100.100.100.200"),
        IPAddr.new("fd00:ec2::254")
      ]
    end
  end
end
