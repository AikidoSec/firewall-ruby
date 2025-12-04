# frozen_string_literal: true

require_relative "../route"
require_relative "protection_settings"

module Aikido::Zen
  # Wraps the list of endpoint protection settings, providing an interface for
  # checking the settings for any given route. If the route has no configured
  # settings, that will return the singleton
  # {RuntimeSettings::ProtectionSettings.none}.
  #
  # @example
  #   endpoint = runtime_settings.endpoints[request.route]
  #   block_request unless endpoint.allows?(request.ip)
  class RuntimeSettings::Endpoints
    # @param data [Array<Hash>]
    # @return [Aikido::Zen::RuntimeSettings::Endpoints]
    def self.from_json(data)
      endpoint_pairs = Array(data).map do |value|
        route = Route.new(verb: value["method"], path: value["route"])
        settings = RuntimeSettings::ProtectionSettings.from_json(value)
        [route, settings]
      end

      # Sort endpoints by wildcard matching order
      endpoint_pairs.sort_by! do |route, settings|
        route.sort_key
      end

      new(endpoint_pairs.to_h)
    end

    # @param endpoints [Hash] the endpoints in wildcard matching order
    # @return [Aikido::Zen::RuntimeSettings::Endpoints]
    def initialize(endpoints = {})
      @endpoints = endpoints
      @endpoints.default = RuntimeSettings::ProtectionSettings.none
    end

    # @param route [Aikido::Zen::Route]
    # @return [Aikido::Zen::RuntimeSettings::ProtectionSettings]
    def [](route)
      return @endpoints[route] if @endpoints.key?(route)

      # Wildcard endpoint matching

      @endpoints.each do |pattern, settings|
        return settings if pattern.match?(route)
      end

      @endpoints.default
    end

    # @param route [Aikido::Zen::Route]
    # @return [Array<Aikido::Zen::RuntimeSettings::ProtectionSettings>]
    def match(route)
      matches = []

      matches << @endpoints[route] if @endpoints.key?(route)

      # Wildcard endpoint matching

      @endpoints.each do |pattern, settings|
        matches << settings if pattern.match?(route)
      end

      matches << @endpoints.default if matches.empty?

      matches
    end

    # @!visibility private
    def ==(other)
      other.is_a?(RuntimeSettings::Endpoints) && to_h == other.to_h
    end

    # @!visibility private
    protected def to_h
      @endpoints
    end
  end
end
