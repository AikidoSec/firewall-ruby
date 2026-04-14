# frozen_string_literal: true

module Aikido::Zen
  # Stores the firewall configuration sourced from the Aikido dashboard. This
  # object is updated by the Agent regularly.
  #
  # Because the RuntimeSettings object can be modified in runtime, it implements
  # the {Observable} API, allowing you to subscribe to updates. These are
  # triggered whenever #update_from_runtime_settings_json makes a change
  # (i.e. if the settings don't change, no update is triggered).
  #
  # You can subscribe to changes with +#add_observer(object, func_name)+, which
  # will call the function passing the settings as an argument
  RuntimeSettings = Struct.new(:updated_at, :heartbeat_interval, :endpoints, :blocked_user_ids, :bypassed_ips, :received_any_stats, :blocking_mode, :blocked_user_agent_regexp, :monitored_user_agent_regexp, :user_agent_details, :blocked_ip_lists, :allowed_ip_lists, :monitored_ip_lists, :block_new_outbound, :domains, :excluded_user_ids_from_rate_limiting) do
    def initialize(*)
      super
      self.endpoints ||= RuntimeSettings::Endpoints.new
      self.bypassed_ips ||= RuntimeSettings::IPSet.new
      self.blocked_ip_lists ||= []
      self.allowed_ip_lists ||= []
      self.monitored_ip_lists ||= []
      self.domains ||= RuntimeSettings::Domains.new
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

    # @!attribute [rw] blocked_ip_lists
    #   @return [Array<Aikido::Zen::RuntimeSettings::IPList>]

    # @!attribute [rw] allowed_ip_lists
    #   @return [Array<Aikido::Zen::RuntimeSettings::IPList>]

    # @!attribute [rw] monitored_ip_lists
    #   @return [Array<Aikido::Zen::RuntimeSettings::IPList>]

    # @!attribute [rw] blocked_user_agent_regexp
    #   @return [Regexp]

    # @!attribute [rw] monitored_user_agent_regexp
    #   @return [Regexp]

    # @!attribute [rw] user_agent_details
    #   @return [Regexp]

    # @!attribute [rw] block_new_outbound
    #   @return [Boolean]

    # @!attribute [rw] domains
    #   @return [Array<Aikido::Zen::RuntimeSettings::DomainSettings>]

    # @!attribute [rw] excluded_user_ids_from_rate_limiting
    #   @return [Array<String>, nil] the user IDs that should be skipped from
    #     rate limiting entirely.

    # Parse and interpret the JSON response from the core API with updated
    # runtime settings, and apply the changes.
    #
    # This will also notify any subscriber to updates.
    #
    # @param data [Hash] the decoded JSON payload from the /api/runtime/config
    #   API endpoint.
    # @return [bool]
    def update_from_runtime_config_json(data)
      last_updated_at = updated_at

      self.updated_at = Time.at(data["configUpdatedAt"].to_i / 1000)
      self.heartbeat_interval = data["heartbeatIntervalInMS"].to_i / 1000
      self.endpoints = RuntimeSettings::Endpoints.from_json(data["endpoints"])
      self.blocked_user_ids = data["blockedUserIds"]
      self.bypassed_ips = RuntimeSettings::IPSet.from_json(data["allowedIPAddresses"])
      self.received_any_stats = data["receivedAnyStats"]
      self.blocking_mode = data["block"]

      self.block_new_outbound = data["blockNewOutgoingRequests"]
      self.domains = RuntimeSettings::Domains.from_json(data["domains"])

      self.excluded_user_ids_from_rate_limiting = data["excludedUserIdsFromRateLimiting"]

      updated_at != last_updated_at
    end

    # Parse and interpret the JSON response from the core API with updated
    # runtime firewall lists, and apply the changes.
    #
    # @param data [Hash] the decoded JSON payload from the /api/runtime/firewall/lists
    #   API endpoint.
    # @return [void]
    def update_from_runtime_firewall_lists_json(data)
      self.blocked_user_agent_regexp = pattern(data["blockedUserAgents"])

      self.monitored_user_agent_regexp = pattern(data["monitoredUserAgents"])

      self.user_agent_details = []

      data["userAgentDetails"]&.each do |record|
        key = record["key"]
        pattern = pattern(record["pattern"])

        next if key.nil? || pattern.nil?

        user_agent_details << {
          key: key,
          pattern: pattern
        }
      end

      # Temporarily disabled: loading blocked/allowed/monitored IP lists from
      # core is O(N) per request in IPListChecker and causes CPU spikes with
      # large lists. Keep the lists empty so the middleware short-circuits.
      self.blocked_ip_lists = []
      self.allowed_ip_lists = []
      self.monitored_ip_lists = []
    end

    # Construct a regular expression from the non-nil and non-empty string,
    # otherwise return nil.
    #
    # The resulting regular expression is case insensitive.
    #
    # @param string [String, nil]
    # @return [Regexp, nil]
    private def pattern(string)
      return nil if string.nil? || string.empty?

      begin
        /#{string}/i
      rescue RegexpError
        nil
      end
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

    # @param user_agent [String] the user agent
    # @return [Boolean] whether the user agent should be blocked
    def blocked_user_agent?(user_agent)
      return false if blocked_user_agent_regexp.nil?

      blocked_user_agent_regexp.match?(user_agent)
    end

    # @param user_agent [String] the user agent
    # @return [Boolean] whether the user agent should be monitored
    def monitored_user_agent?(user_agent)
      return false if monitored_user_agent_regexp.nil?

      monitored_user_agent_regexp.match?(user_agent)
    end

    # @param user_agent [String] the user agent
    # @return [Array<String>] the matching user agent keys
    def user_agent_keys(user_agent)
      return [] if user_agent_details.nil?

      user_agent_details.filter_map { |record| record[:key] if record[:pattern].match?(user_agent) }
    end

    def allowed_ip?(ip)
      allowed_ip_lists.empty? || allowed_ip_lists.any? { |ip_list| ip_list.include?(ip) }
    end

    def blocked_ip?(ip)
      blocked_ip_lists.any? { |ip_list| ip_list.include?(ip) }
    end

    def monitored_ip?(ip)
      monitored_ip_lists.any? { |ip_list| ip_list.include?(ip) }
    end

    def monitored_ip_list_keys(ip)
      return [] if ip.nil?

      monitored_ip_lists.filter_map { |ip_list| ip_list.key if ip_list.include?(ip) }
    end

    def block_outbound?(connection)
      domain = domains[connection.host]

      return true if !domain.equal?(RuntimeSettings::DomainSettings.none) && domain.block?

      block_new_outbound && domain.block?
    end
  end
end

require_relative "runtime_settings/ip_set"
require_relative "runtime_settings/ip_list"
require_relative "runtime_settings/endpoints"
require_relative "runtime_settings/domains"
