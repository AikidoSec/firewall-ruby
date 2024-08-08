# frozen_string_literal: true

require_relative "errors"

require_relative "agent"

require_relative "firewall/version"
require_relative "firewall/settings"
require_relative "firewall/vulnerabilities"

module Aikido
  module Firewall
    # @return [Aikido::Firewall::Settings] the firewall configuration sourced
    #   from your Aikido dashboard. This is periodically polled for updates.
    def self.settings
      @settings ||= Aikido::Firewall::Settings.new
    end

    # Load all sinks matching libraries loaded into memory. This method should
    # be called after all other dependencies have been loaded into memory (i.e.
    # at the end of the initialization process).
    #
    # If a new gem is required, this method can be called again safely.
    #
    # @return [void]
    def self.initialize!
      require_relative "firewall/sinks"
    end
  end
end
