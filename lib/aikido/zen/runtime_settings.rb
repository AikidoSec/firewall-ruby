# frozen_string_literal: true

require "set"

module Aikido::Zen
  RuntimeSettings = Struct.new(
    :updated_at,
    :heartbeat_interval,
    :endpoints,
    :blocked_user_ids,
    :bypassed_ips,
    :received_any_stats,
    :blocking_mode,
    :block_new_outbound,
    :domains,
    :excluded_user_ids_from_rate_limiting,
    :enabled_features
  ) do
    def initialize(*)
      super
      self.endpoints ||= RuntimeSettings::Endpoints.new
      self.bypassed_ips ||= RuntimeSettings::IPSet.new
      self.domains ||= RuntimeSettings::Domains.new
      self.enabled_features ||= Set.new
    end

    # @!attribute [rw] updated_at
    #   @return [Time] when these settings were updated in the Aikido dashboard.

    # @!attribute [rw] heartbeat_interval
    #   @return [Integer] duration in seconds between heartbeat requests to the
    #     Aikido server.

    # @!attribute [rw] endpoints
    #   @return [Aikido::Zen::RuntimeSettings::Endpoints]

    # @!attribute [rw] blocked_user_ids
    #   @return [Array]

    # @!attribute [rw] bypassed_ips
    #   @return [Aikido::Zen::RuntimeSettings::IPSet]

    # @!attribute [rw] received_any_stats
    #   @return [Boolean] whether the Aikido server has received any data from
    #     this application.

    # @!attribute [rw] blocking_mode
    #   @return [Boolean]

    # @!attribute [rw] block_new_outbound
    #   @return [Boolean]

    # @!attribute [rw] domains
    #   @return [Array<Aikido::Zen::RuntimeSettings::DomainSettings>]

    # @!attribute [rw] excluded_user_ids_from_rate_limiting
    #   @return [Array<String>, nil] the user IDs that should be skipped from
    #     rate limiting entirely.

    # @!attribute [rw] enabled_features
    #   @return [Set<String>]

    # @param data [Hash] the decoded JSON payload from the /api/runtime/config
    # @return [Boolean]
    def update_from_json(data)
      last_updated_at = updated_at

      self.updated_at = Time.at(data["configUpdatedAt"].to_i)
      self.heartbeat_interval = data["heartbeatIntervalInMS"].to_i / 1000
      self.endpoints = RuntimeSettings::Endpoints.from_json(data["endpoints"])
      self.blocked_user_ids = data["blockedUserIds"]
      self.bypassed_ips = RuntimeSettings::IPSet.from_json(data["allowedIPAddresses"])
      self.received_any_stats = data["receivedAnyStats"]
      self.blocking_mode = data["block"]

      self.block_new_outbound = data["blockNewOutgoingRequests"]
      self.domains = RuntimeSettings::Domains.from_json(data["domains"])

      self.excluded_user_ids_from_rate_limiting = data["excludedUserIdsFromRateLimiting"]

      self.enabled_features = Set.new(data["enabledFeatures"])

      updated_at != last_updated_at
    end

    # @param ip [String]
    # @return [Boolean] Whether the IP is included in the bypassed IPs set.
    def bypassed_ip?(ip)
      bypassed_ips.include?(ip)
    end

    # @param user_id [String, nil]
    # @return [Boolean] Whether the user is excluded from rate limiting.
    def user_excluded_from_rate_limiting?(user_id)
      return false if user_id.nil?
      excluded_user_ids_from_rate_limiting&.include?(user_id.to_s) || false
    end

    def block_outbound?(connection)
      domain = domains[connection.host]

      (!domain.nil? && domain.block?) || (domain.nil? && block_new_outbound)
    end

    private def enabled_feature?(feature)
      enabled_features.include?(feature)
    end

    def realtime_settings_updates_enabled?
      enabled_feature?("realtime_updates")
    end
  end
end

require_relative "runtime_settings/ip_set"
require_relative "runtime_settings/endpoints"
require_relative "runtime_settings/domains"
