# frozen_string_literal: true

require_relative "ip_set"
require_relative "rate_limit_settings"

module Aikido::Zen
  # Models the settings for a given Route as configured in the Aikido UI.
  class RuntimeSettings::ProtectionSettings
    # @return [Aikido::Zen::RuntimeSettings::ProtectionSettings] singleton
    #   instance for endpoints with no configured protections on a given route,
    #   that can be used as a default value for routes.
    def self.none
      @no_settings ||= new
    end

    # Initialize settings from an API response.
    #
    # @param data [Hash] the deserialized JSON data.
    # @option data [Boolean] "forceProtectionOff" whether the user has
    #   disabled attack protection for this route.
    # @option data [Array<String>] "allowedIPAddresses" the list of IPs that
    #   can make requests to this endpoint.
    # @option data [Hash] "rateLimiting" the rate limiting options for this
    #   endpoint. See {Aikido::Zen::RuntimeSettings::RateLimitSettings.from_json}.
    #
    # @return [Aikido::Zen::RuntimeSettings::ProtectionSettings]
    # @raise [IPAddr::InvalidAddressError] if any of the IPs in
    #   "allowedIPAddresses" is not a valid address or family.
    def self.from_json(data)
      ips = RuntimeSettings::IPSet.from_json(data["allowedIPAddresses"])
      rate_limiting = RuntimeSettings::RateLimitSettings.from_json(data["rateLimiting"])

      new(
        protected: !data["forceProtectionOff"],
        allowed_ips: ips,
        rate_limiting: rate_limiting
      )
    end

    # @return [Aikido::Zen::RuntimeSettings::IPSet] list of IP addresses which
    #   are allowed to make requests on this route. If empty, all IP addresses
    #   are allowed.
    attr_reader :allowed_ips

    # @return [Aikido::Zen::RuntimeSettings::RateLimitSettings]
    attr_reader :rate_limiting

    def initialize(
      protected: true,
      allowed_ips: RuntimeSettings::IPSet.new,
      rate_limiting: RuntimeSettings::RateLimitSettings.disabled
    )
      @protected = !!protected
      @rate_limiting = rate_limiting
      @allowed_ips = allowed_ips
    end

    def protected?
      @protected
    end
  end
end
