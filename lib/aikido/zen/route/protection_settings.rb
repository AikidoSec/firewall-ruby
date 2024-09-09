# frozen_string_literal: true

module Aikido::Zen
  class Route
    # Models the settings for a given Route as configured in the Aikido UI.
    class ProtectionSettings
      # @return [Aikido::Zen::Route::ProtectionSettings] singleton instance for
      #   endpoints with no configured protections on a given route, that can be
      #   used as a default value for routes.
      def self.none
        @no_settings ||= new
      end

      # Initialize settings from an API response.
      #
      # @param data [Hash] the deserialized JSON data.
      # @option data [Boolean] "forceProtectionOff" whether the user has
      #   disabled attack protection for this route.
      #
      # @return [Aikido::Zen::Route::ProtectionSettings]
      def self.from_json(data)
        new(protected: !data["forceProtectionOff"])
      end

      def initialize(protected: true)
        @protected = !!protected
      end

      def protected?
        @protected
      end
    end
  end
end
