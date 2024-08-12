# frozen_string_literal: true

require "socket"
require "rubygems"

require_relative "package"

module Aikido::Agent
  # Provides information about the currently running Agent.
  class Info
    def initialize(config = Aikido::Agent.config)
      @config = config
    end

    def attacks_block_requests?
      !!@config.blocking_mode
    end

    def attacks_are_only_reported?
      !attacks_block_requests?
    end

    def library_name
      "firewall-ruby"
    end

    def library_version
      VERSION
    end

    def hostname
      @hostname ||= Socket.gethostname
    end

    # @return [Array<Aikido::Agent::Package>] a list of loaded rubygems.
    def packages
      @packages ||= Gem.loaded_specs.map { |_, spec| Package.new(spec.name, spec.version) }
    end

    # @return [String] the first non-loopback IPv4 address that we can use
    #   to identify this host. If the machine is solely identified by IPv6
    #   addresses, then this will instead return an IPv6 address.
    def ip_address
      @ip_address ||= Socket.ip_address_list
        .reject { |ip| ip.ipv4_loopback? || ip.ipv6_loopback? || ip.unix? }
        .min_by { |ip| ip.ipv4? ? 0 : 1 }
        .ip_address
    end

    def os_name
      Gem::Platform.local.os
    end

    def os_version
      Gem::Platform.local.version
    end

    def as_json
      {
        dryMode: attacks_are_only_reported?,
        library: library_name,
        version: library_version,
        hostname: hostname,
        ipAddress: ip_address,
        os: {name: os_name, version: os_version},
        packages: packages.reduce({}) { |all, package| all.update(package.as_json) },
        incompatiblePackages: {},
        stack: [],
        serverless: false,
        nodeEnv: "",
        preventedPrototypePollution: false
      }
    end
  end
end
