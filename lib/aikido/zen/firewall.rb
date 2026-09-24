# frozen_string_literal: true

require "fileutils"

module Aikido::Zen
  class Firewall
    # @return [Regexp, nil]
    attr_accessor :blocked_user_agent_regexp

    # @return [Regexp, nil]
    attr_accessor :monitored_user_agent_regexp

    # @return [Array<Hash>, nil]
    attr_accessor :user_agent_details

    # @return [Aikido::Zen::Firewall::IPLists, nil]
    attr_accessor :blocked_ip_lists

    # @return [Aikido::Zen::Firewall::IPLists, nil]
    attr_accessor :allowed_ip_lists

    # @return [Aikido::Zen::Firewall::IPLists, nil]
    attr_accessor :monitored_ip_lists

    def initialize(zen: Aikido::Zen, ip_lists_dir: zen.config.ip_lists_dir)
      @zen = zen
      @ip_lists_dir = ip_lists_dir

      FileUtils.mkdir_p(@ip_lists_dir)
    end

    def update_user_agents_from_json(data)
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
    end

    # @param data [Hash] the decoded JSON payload from /api/runtime/firewall/lists
    # @return [void]
    def update_ip_lists_from_json(data)
      IPLists.write_from_json(ip_list_path("blocked"), data["blockedIPAddresses"])
      IPLists.write_from_json(ip_list_path("allowed"), data["allowedIPAddresses"])
      IPLists.write_from_json(ip_list_path("monitored"), data["monitoredIPAddresses"])

      reload_ip_lists
    end

    # Reopens each of the IPLists files.
    #
    # Forked workers call this directly, trusting that the main process has already
    # written via #update_ip_lists_from_json.
    def reload_ip_lists
      self.blocked_ip_lists = reload_ip_list(blocked_ip_lists, "blocked")
      self.allowed_ip_lists = reload_ip_list(allowed_ip_lists, "allowed")
      self.monitored_ip_lists = reload_ip_list(monitored_ip_lists, "monitored")
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
      allowed_ip_lists.nil? || allowed_ip_lists.empty? || allowed_ip_lists.include?(ip)
    end

    def blocked_ip?(ip)
      !blocked_ip_lists.nil? && blocked_ip_lists.include?(ip)
    end

    def monitored_ip?(ip)
      !monitored_ip_lists.nil? && monitored_ip_lists.include?(ip)
    end

    # @param ip [String, nil]
    # @return [Array<Aikido::Zen::Firewall::IPLists::IPList>]
    def matching_blocked_ip_lists(ip)
      blocked_ip_lists&.matching_ip_lists(ip) || []
    end

    # @param ip [String, nil]
    # @return [Array<Aikido::Zen::Firewall::IPLists::IPList>]
    def matching_monitored_ip_lists(ip)
      monitored_ip_lists&.matching_ip_lists(ip) || []
    end

    private

    # Construct a regular expression from the non-nil and non-empty string,
    # otherwise return nil.
    #
    # The resulting regular expression is case insensitive.
    #
    # @param string [String, nil]
    # @return [Regexp, nil]
    def pattern(string)
      return nil if string.nil? || string.empty?

      begin
        /#{string}/i
      rescue RegexpError
        nil
      end
    end

    def ip_list_path(name)
      "#{@ip_lists_dir}/#{name}.ipls"
    end

    def reload_ip_list(old_ip_list, name)
      new_ip_list = IPLists.new(ip_list_path(name))
      old_ip_list&.close
      new_ip_list
    rescue Errno::ENOENT, Aikido::Zen::IPLists::FormatError
      old_ip_list
    end
  end
end

require_relative "firewall/ip_lists"
