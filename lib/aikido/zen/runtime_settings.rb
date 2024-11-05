# frozen_string_literal: true

module Aikido::Zen
  # Stores the firewall configuration sourced from the Aikido dashboard. This
  # object is updated by the Agent regularly.
  #
  # Because the RuntimeSettings object can be modified in runtime, it implements
  # the {Observable} API, allowing you to subscribe to updates. These are
  # triggered whenever #update_from_json makes a change (i.e. if the settings
  # don't change, no update is triggered).
  #
  # You can subscribe to changes with +#add_observer(object, func_name)+, which
  # will call the function passing the settings as an argument.
  RuntimeSettings = Struct.new(:updated_at, :heartbeat_interval, :endpoints, :blocked_user_ids, :skip_protection_for_ips, :received_any_stats) do
    def initialize(*)
      super
      self.endpoints ||= RuntimeSettings::Endpoints.new
      self.skip_protection_for_ips ||= RuntimeSettings::IPSet.new
    end

    # @!attribute [rw] updated_at
    #   @return [Time] when these settings were updated in the Aikido dashboard.

    # @!attribute [rw] heartbeat_interval
    #   @return [Integer] duration in seconds between heartbeat requests to the
    #     Aikido server.

    # @!attribute [rw] received_any_stats
    #   @return [Boolean] whether the Aikido server has received any data from
    #     this application.

    # @!attribute [rw] endpoints
    #   @return [Aikido::Zen::RuntimeSettings::Endpoints]

    # @!attribute [rw] blocked_user_ids
    #   @return [Array]

    # @!attribute [rw] skip_protection_for_ips
    #   @return [Aikido::Zen::RuntimeSettings::IPSet]

    # Parse and interpret the JSON response from the core API with updated
    # settings, and apply the changes. This will also notify any subscriber
    # to updates
    #
    # @param data [Hash] the decoded JSON payload from the /api/runtime/config
    #   API endpoint.
    #
    # @return [void]
    def update_from_json(data)
      last_updated_at = updated_at

      self.updated_at = Time.at(data["configUpdatedAt"].to_i / 1000)
      self.heartbeat_interval = (data["heartbeatIntervalInMS"].to_i / 1000)
      self.endpoints = RuntimeSettings::Endpoints.from_json(data["endpoints"])
      self.blocked_user_ids = data["blockedUserIds"]
      self.skip_protection_for_ips = RuntimeSettings::IPSet.from_json(data["allowedIPAddresses"])
      self.received_any_stats = data["receivedAnyStats"]

      Aikido::Zen.agent.updated_settings! if updated_at != last_updated_at
    end
  end
end

require_relative "runtime_settings/ip_set"
require_relative "runtime_settings/endpoints"
