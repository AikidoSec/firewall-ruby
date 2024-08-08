# frozen_string_literal: true

module Aikido::Firewall
  # Stores the firewall configuration sourced from the Aikido dashboard. This
  # object is updated by the Agent regularly.
  class Settings < Concurrent::MutableStruct.new(
    :updated_at, :heartbeat_interval, :endpoints, :blocked_user_ids, :allowed_ip_addresses, :received_any_stats
  )
    # @!attribute [rw] updated_at
    #   @return [Time] when these settings were updated in the Aikido dashboard.

    # @!attribute [rw] heartbeat_interval
    #   @return [Integer] duration in seconds between heartbeat requests to the
    #     Aikido server.

    # @!attribute [rw] received_any_stats
    #   @return [Boolean] whether the Aikido server has received any data from
    #     this application.

    # @!attribute [rw] endpoints
    #   @return [Array]

    # @!attribute [rw] blocked_user_ids
    #   @return [Array]

    # @!attribute [rw] allowed_ip_addresses
    #   @return [Array]

    # Parse and interpret the JSON response from the core API with updated
    # settings, and apply the changes.
    #
    # @param data [Hash] the decoded JSON payload from the /api/runtime/config
    #   API endpoint.
    #
    # @return [void]
    def update_from_json(data)
      self.updated_at = Time.at(data["configUpdatedAt"].to_i)
      self.heartbeat_interval = (data["heartbeatIntervalInMS"].to_i / 1000)
      self.endpoints = data["endpoints"]
      self.blocked_user_ids = data["blockedUserIds"]
      self.allowed_ip_addresses = data["allowedIpAddresses"]
      self.received_any_stats = data["receivedAnyStats"]
    end
  end
end
