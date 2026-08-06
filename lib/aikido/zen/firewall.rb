# frozen_string_literal: true

require "fileutils"

module Aikido::Zen
  # Firewall lists (blocked/allowed/monitored IPs, user-agent patterns)
  # synced from the Aikido dashboard.
  class Firewall
    # The shape `IPLists::Data::Writer.write` needs for one IP list: a key
    # and description for attribution, plus its addresses pre-grouped into
    # sorted ipv4/ipv6 integer ranges. See #build_ip_list_entry.
    IPListEntry = Struct.new(:key, :description, :ipv4_ranges, :ipv6_ranges)
    private_constant :IPListEntry

    # @return [Regexp, nil]
    attr_accessor :blocked_user_agent_regexp

    # @return [Regexp, nil]
    attr_accessor :monitored_user_agent_regexp

    # @return [Array<Hash>, nil]
    attr_accessor :user_agent_details

    # @return [Aikido::Zen::IPLists::Data::Reader, nil] nil until the first
    #   successful sync -- see #update_from_json.
    attr_accessor :blocked_ip_lists

    # @return [Aikido::Zen::IPLists::Data::Reader, nil] nil until the first
    #   successful sync -- see #update_from_json.
    attr_accessor :allowed_ip_lists

    # @return [Aikido::Zen::IPLists::Data::Reader, nil] nil until the first
    #   successful sync -- see #update_from_json.
    attr_accessor :monitored_ip_lists

    # @param data [Hash] the decoded JSON payload from /api/runtime/firewall/lists
    # @param write_ip_lists [Boolean]
    # @param ip_lists_directory [String]
    # @return [Boolean]
    def update_from_json(data, write_ip_lists: true, ip_lists_directory: Aikido::Zen.config.ip_lists_dir)
      apply_user_agents(data)

      if write_ip_lists
        write_ip_list_file(ip_lists_directory, "blocked", data["blockedIPAddresses"])
        write_ip_list_file(ip_lists_directory, "allowed", data["allowedIPAddresses"])
        write_ip_list_file(ip_lists_directory, "monitored", data["monitoredIPAddresses"])
      end

      reopen_ip_list_readers(ip_lists_directory)

      true
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

    # @param ip [String]
    # @return [Boolean] true if there's no allow list configured at all
    #   (meaning everyone's allowed), or if +ip+ is in it.
    def allowed_ip?(ip)
      allowed_ip_lists.nil? || allowed_ip_lists.empty? || allowed_ip_lists.include?(ip)
    end

    # @param ip [String]
    # @return [Boolean]
    def blocked_ip?(ip)
      !blocked_ip_lists.nil? && blocked_ip_lists.include?(ip)
    end

    # @param ip [String]
    # @return [Boolean]
    def monitored_ip?(ip)
      !monitored_ip_lists.nil? && monitored_ip_lists.include?(ip)
    end

    # @param ip [String, nil]
    # @return [Array<String>] the keys of every monitored list +ip+ matches
    def monitored_ip_list_keys(ip)
      monitored_ip_lists&.matching_lists(ip)&.map(&:key) || []
    end

    # @param ip [String, nil]
    # @return [Array<Aikido::Zen::IPLists::Data::Reader::Match>] every
    #   blocked list +ip+ matches, empty if none (or none configured)
    def matching_blocked_lists(ip)
      blocked_ip_lists&.matching_lists(ip) || []
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

    # @param data [Hash]
    private def apply_user_agents(data)
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

    # @param directory [String]
    # @param name [String] "blocked", "allowed", or "monitored"
    # @param raw_ip_lists [Array<Hash>, nil]
    private def write_ip_list_file(directory, name, raw_ip_lists)
      FileUtils.mkdir_p(directory)

      ip_lists = Array(raw_ip_lists).map { |ip_list| build_ip_list_entry(ip_list) }
      Aikido::Zen::IPLists::Data::Writer.write(ip_list_file_path(directory, name), ip_lists)
    end

    # Groups one raw JSON IP list's addresses into sorted ipv4/ipv6 integer
    # ranges -- the shape `IPLists::Data::Writer.write` expects (`#key`,
    # `#description`, `#ipv4_ranges`, `#ipv6_ranges`).
    #
    # @param raw_ip_list [Hash]
    # @return [#key, #description, #ipv4_ranges, #ipv6_ranges]
    private def build_ip_list_entry(raw_ip_list)
      ipv4_ranges = []
      ipv6_ranges = []

      Array(raw_ip_list["ips"]).each do |ip|
        address = IPAddr.new(ip)
        range = address.to_range
        ip_int_range = (range.begin.to_i..range.end.to_i)

        if address.ipv4?
          ipv4_ranges << ip_int_range
        elsif address.ipv6?
          ipv6_ranges << ip_int_range
        else
          raise ArgumentError, "Unsupported IP address family: #{address.inspect}"
        end
      end

      IPListEntry.new(
        raw_ip_list["key"],
        raw_ip_list["description"],
        ipv4_ranges.sort_by(&:begin),
        ipv6_ranges.sort_by(&:begin)
      )
    end

    # @param directory [String]
    private def reopen_ip_list_readers(directory)
      self.blocked_ip_lists = reopen_ip_list_reader(directory, "blocked", blocked_ip_lists)
      self.allowed_ip_lists = reopen_ip_list_reader(directory, "allowed", allowed_ip_lists)
      self.monitored_ip_lists = reopen_ip_list_reader(directory, "monitored", monitored_ip_lists)
    end

    # Closes +previous_reader+ (if any) and opens a fresh one for +name+,
    # picking up whatever's currently written to disk. Falls back to keeping
    # +previous_reader+ if the file doesn't exist yet (a forked worker's
    # first sync could in principle race ahead of the master's first write)
    # or looks corrupt.
    #
    # @param directory [String]
    # @param name [String] "blocked", "allowed", or "monitored"
    # @param previous_reader [Aikido::Zen::IPLists::Data::Reader, nil]
    # @return [Aikido::Zen::IPLists::Data::Reader, nil]
    private def reopen_ip_list_reader(directory, name, previous_reader)
      reader = Aikido::Zen::IPLists::Data::Reader.new(ip_list_file_path(directory, name))
      previous_reader&.close
      reader
    rescue Errno::ENOENT, Aikido::Zen::IPLists::Data::IPList::Reader::FormatError
      previous_reader
    end

    private def ip_list_file_path(directory, name)
      "#{directory}/#{name}.ipls"
    end
  end
end
