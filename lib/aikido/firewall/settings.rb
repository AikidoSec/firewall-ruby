# frozen_string_literal: true

module Aikido::Firewall
  # Stores the firewall configuration sourced from the Aikido dashboard. This
  # object is updated by the Agent regularly.
  class Settings
    # @return [Time]
    attr_accessor :updated_at

    # @return [Integer] duration in seconds between heartbeat requests to the
    #   Aikido server.
    attr_accessor :heartbeat_interval

    attr_accessor :endpoints

    attr_accessor :blocked_user_ids

    attr_accessor :allowed_ip_addresses

    # @return [Boolean] whether the Aikido server has received any data from
    #   this application.
    attr_accessor :received_any_stats

    # @return [Boolean] whether we have successfully gotten data from the API.
    def loaded?
      @loaded
    end

    # Parse and interpret the JSON response from the core API with updated
    # settings, and apply the changes.
    #
    # @param data [Hash] the decoded JSON payload from the /api/runtime/config
    #   API endpoint.
    #
    # @return [void]
    def update_from_json(data)
      @loaded = true

      self.updated_at = Time.at(data["configUpdatedAt"].to_i)
      self.heartbeat_interval = (data["heartbeatIntervalInMS"].to_i / 1000)
      self.endpoints = data["endpoints"]
      self.blocked_user_ids = data["blockedUserIds"]
      self.allowed_ip_addresses = data["allowedIpAddresses"]
      self.received_any_stats = data["receivedAnyStats"]
    end
  end
end
