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
  class RuntimeSettings
    def initialize
      @updated_at = nil
      @heartbeat_interval = nil
      @endpoints = RuntimeSettings::Endpoints.new
      @blocked_user_ids = nil
      @bypassed_ips = RuntimeSettings::IPSet.new
      @received_any_stats = nil
      @blocking_mode = nil
      @blocked_user_agent_regexp = nil
      @monitored_user_agent_regexp = nil
      @user_agent_details = nil
      @blocked_ip_lists = []
      @allowed_ip_lists = []
      @monitored_ip_lists = []
      @block_new_outbound = nil
      @domains = RuntimeSettings::Domains.new
      @excluded_user_ids_from_rate_limiting = nil
    end

    # @return [Time] when these settings were updated in the Aikido dashboard
    attr_accessor :updated_at

    # @return [Integer] duration in seconds between heartbeat requests to the Aikido server.
    attr_accessor :heartbeat_interval

    # @return [Aikido::Zen::RuntimeSettings::Endpoints]
    attr_accessor :endpoints

    # @return [Array]
    attr_accessor :blocked_user_ids

    # @return [Aikido::Zen::RuntimeSettings::IPSet]
    attr_accessor :bypassed_ips

    # @return [Boolean] whether the Aikido server has received any data from this application.
    attr_accessor :received_any_stats

    # @return [Boolean]
    attr_accessor :blocking_mode

    # @return [Array<Aikido::Zen::RuntimeSettings::IPList>]
    attr_accessor :blocked_ip_lists

    # @return [Array<Aikido::Zen::RuntimeSettings::IPList>]
    attr_accessor :allowed_ip_lists

    # @return [Array<Aikido::Zen::RuntimeSettings::IPList>]
    attr_accessor :monitored_ip_lists

    # @return [Regexp]
    attr_accessor :blocked_user_agent_regexp

    # @return [Regexp]
    attr_accessor :monitored_user_agent_regexp

    # @return [Regexp]
    attr_accessor :user_agent_details

    # @return [Boolean]
    attr_accessor :block_new_outbound

    # @return [Array<Aikido::Zen::RuntimeSettings::DomainSettings>]
    attr_accessor :domains

    # @return [Array<String>, nil] the user IDs that should be skipped from rate limiting entirely
    attr_accessor :excluded_user_ids_from_rate_limiting

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

      @updated_at = Time.at(data["configUpdatedAt"].to_i / 1000)
      @heartbeat_interval = data["heartbeatIntervalInMS"].to_i / 1000
      @endpoints = RuntimeSettings::Endpoints.from_json(data["endpoints"])
      @blocked_user_ids = data["blockedUserIds"]
      @bypassed_ips = RuntimeSettings::IPSet.from_json(data["allowedIPAddresses"])
      @received_any_stats = data["receivedAnyStats"]
      @blocking_mode = data["block"]

      @block_new_outbound = data["blockNewOutgoingRequests"]
      @domains = RuntimeSettings::Domains.from_json(data["domains"])

      @excluded_user_ids_from_rate_limiting = data["excludedUserIdsFromRateLimiting"]

      @updated_at != last_updated_at
    end

    # Parse and interpret the JSON response from the core API with updated
    # runtime firewall lists, and apply the changes.
    #
    # @param data [Hash] the decoded JSON payload from the /api/runtime/firewall/lists
    #   API endpoint.
    # @return [void]
    def update_from_runtime_firewall_lists_json(data)
      @blocked_user_agent_regexp = pattern(data["blockedUserAgents"])

      @monitored_user_agent_regexp = pattern(data["monitoredUserAgents"])

      @user_agent_details = []

      data["userAgentDetails"]&.each do |record|
        key = record["key"]
        pattern = pattern(record["pattern"])

        next if key.nil? || pattern.nil?

        @user_agent_details << {
          key: key,
          pattern: pattern
        }
      end

      @blocked_ip_lists = []

      data["blockedIPAddresses"]&.each do |ip_list|
        @blocked_ip_lists << RuntimeSettings::IPList.from_json(ip_list)
      end

      @allowed_ip_lists = []

      data["allowedIPAddresses"]&.each do |ip_list|
        @allowed_ip_lists << RuntimeSettings::IPList.from_json(ip_list)
      end

      @monitored_ip_lists = []

      data["monitoredIPAddresses"]&.each do |ip_list|
        @monitored_ip_lists << RuntimeSettings::IPList.from_json(ip_list)
      end
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
      @bypassed_ips.include?(ip)
    end

    # @param user_id [String, nil]
    # @return [Boolean] Whether the user is excluded from rate limiting.
    def user_excluded_from_rate_limiting?(user_id)
      return false if user_id.nil?

      @excluded_user_ids_from_rate_limiting&.include?(user_id.to_s) || false
    end

    # @param user_agent [String] the user agent
    # @return [Boolean] whether the user agent should be blocked
    def blocked_user_agent?(user_agent)
      return false if blocked_user_agent_regexp.nil?

      @blocked_user_agent_regexp.match?(user_agent)
    end

    # @param user_agent [String] the user agent
    # @return [Boolean] whether the user agent should be monitored
    def monitored_user_agent?(user_agent)
      return false if @monitored_user_agent_regexp.nil?

      @monitored_user_agent_regexp.match?(user_agent)
    end

    # @param user_agent [String] the user agent
    # @return [Array<String>] the matching user agent keys
    def user_agent_keys(user_agent)
      return [] if @user_agent_details.nil?

      @user_agent_details.filter_map { |record| record[:key] if record[:pattern].match?(user_agent) }
    end

    def allowed_ip?(ip)
      @allowed_ip_lists.empty? || @allowed_ip_lists.any? { |ip_list| ip_list.include?(ip) }
    end

    def blocked_ip?(ip)
      @blocked_ip_lists.any? { |ip_list| ip_list.include?(ip) }
    end

    def monitored_ip?(ip)
      @monitored_ip_lists.any? { |ip_list| ip_list.include?(ip) }
    end

    def monitored_ip_list_keys(ip)
      return [] if ip.nil?

      @monitored_ip_lists.filter_map { |ip_list| ip_list.key if ip_list.include?(ip) }
    end

    def block_outbound?(connection)
      domain = @domains[connection.host]

      return true if !domain.equal?(RuntimeSettings::DomainSettings.none) && domain.block?

      @block_new_outbound && domain.block?
    end
  end
end

require_relative "runtime_settings/ip_set"
require_relative "runtime_settings/ip_list"
require_relative "runtime_settings/endpoints"
require_relative "runtime_settings/domains"
