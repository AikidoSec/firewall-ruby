# frozen_string_literal: true

module Aikido::Zen
  class Firewall
    # @return [Regexp, nil]
    attr_accessor :blocked_user_agent_regexp

    # @return [Regexp, nil]
    attr_accessor :monitored_user_agent_regexp

    # @return [Array<Hash>, nil]
    attr_accessor :user_agent_details

    # @return [Array<Aikido::Zen::Firewall::IPList>]
    attr_accessor :blocked_ip_lists

    # @return [Array<Aikido::Zen::Firewall::IPList>]
    attr_accessor :allowed_ip_lists

    # @return [Array<Aikido::Zen::Firewall::IPList>]
    attr_accessor :monitored_ip_lists

    def initialize
      self.blocked_ip_lists = []
      self.allowed_ip_lists = []
      self.monitored_ip_lists = []
    end

    # @param data [Hash] the decoded JSON payload from /api/runtime/firewall/lists
    # @return [Boolean] whether the firewall was updated. Nothing is replaced
    #   unless all IP lists are created.
    def update_from_json(data)
      new_blocked_ip_lists = []

      data["blockedIPAddresses"]&.each do |ip_list|
        new_blocked_ip_lists << Firewall::IPList.from_json(ip_list)
      end

      new_allowed_ip_lists = []

      data["allowedIPAddresses"]&.each do |ip_list|
        new_allowed_ip_lists << Firewall::IPList.from_json(ip_list)
      end

      new_monitored_ip_lists = []

      data["monitoredIPAddresses"]&.each do |ip_list|
        new_monitored_ip_lists << Firewall::IPList.from_json(ip_list)
      end

      new_user_agent_details = []

      data["userAgentDetails"]&.each do |record|
        key = record["key"]
        pattern = pattern(record["pattern"])

        next if key.nil? || pattern.nil?

        new_user_agent_details << {
          key: key,
          pattern: pattern
        }
      end

      # Nothing is replaced unless every IP matcher was built successfully,
      # so requests stay protected by the current rule set.
      self.blocked_user_agent_regexp = pattern(data["blockedUserAgents"])
      self.monitored_user_agent_regexp = pattern(data["monitoredUserAgents"])
      self.blocked_ip_lists = new_blocked_ip_lists
      self.allowed_ip_lists = new_allowed_ip_lists
      self.monitored_ip_lists = new_monitored_ip_lists
      self.user_agent_details = new_user_agent_details

      true
    rescue ArgumentError, InternalsError => err
      Aikido::Zen.config.logger.error("Zen failed to update the firewall lists: #{err.message}")
      false
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
  end
end

require_relative "firewall/ip_list"
