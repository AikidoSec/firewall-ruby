# frozen_string_literal: true

require "socket"
require "securerandom"
require "rubygems"

require_relative "package"

module Aikido::Zen
  # Provides information about the currently running agent.
  class SystemInfo
    # @return [String] a unique identifier for the currently running agent.
    attr_reader :session_id

    def initialize
      @session_id = generate_session_id
    end

    def attacks_block_requests?
      !!Aikido::Zen.blocking_mode?
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

    def platform_version
      RUBY_VERSION
    end

    # @return [String, nil] the hostname, or nil if it cannot be determined.
    def hostname
      @hostname ||= begin
        name = Socket.gethostname.to_s
        name unless name.empty?
      rescue SystemCallError
        nil
      end
    end

    # Headers sent with every request to the Aikido server to describe and
    # identify the currently running agent.
    #
    # @return [Hash{String => String}] the agent headers, keyed by header name.
    def agent_headers
      {
        "X-Agent-Platform" => "ruby",
        "X-Agent-Library" => library_name,
        "X-Agent-Version" => library_version,
        "X-Agent-Hostname" => hostname || "unknown",
        "X-Agent-IP-Address" => ip_address || "unknown",
        "X-Agent-Session-Id" => session_id
      }
    end

    # @return [Array<Aikido::Zen::Package>] a list of loaded rubygems that are
    #   supported by Aikido (i.e. we have a Sink that scans the package for
    #   vulnerabilities and protects you).
    def packages
      @packages ||= Gem.loaded_specs
        .map { |_, spec| Package.new(spec.name, spec.version) }
        .select(&:supported?)
    end

    # Find the first non-loopback IP address, preferring IPv4.
    #
    # @return [String, nil] the IP address, or nil if it cannot be determined.
    def ip_address
      @ip_address ||= begin
        address = Socket.ip_address_list
          .reject { |ip| ip.ipv4_loopback? || ip.ipv6_loopback? || ip.unix? }
          .min_by { |ip| ip.ipv4? ? 0 : 1 }
        address&.ip_address
      rescue SystemCallError
        nil
      end
    end

    def os_name
      Gem::Platform.local.os
    end

    def os_version
      Gem::Platform.local.version || "unknown"
    end

    def as_json
      {
        "dryMode" => attacks_are_only_reported?,
        "library" => library_name,
        "version" => library_version,
        "hostname" => hostname,
        "ipAddress" => ip_address,
        "platform" => {"version" => platform_version},
        "os" => {"name" => os_name, "version" => os_version},
        "packages" => packages.reduce({}) { |all, package| all.update(package.as_json) },
        "incompatiblePackages" => {},
        "stack" => [],
        "serverless" => false,
        "nodeEnv" => "",
        "preventedPrototypePollution" => false
      }
    end

    private def generate_session_id
      # Code coverage is disabled here because `SecureRandom.uuid_v7` is only
      # defined in Ruby 3.3+.
      # :nocov:
      if SecureRandom.respond_to?(:uuid_v7)
        SecureRandom.uuid_v7
      else
        SecureRandom.uuid
      end
      # :nocov:
    end
  end
end
