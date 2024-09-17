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
      data = Array(data).map { |item|
        route = Route.new(verb: item["method"], path: item["route"])
        settings = RuntimeSettings::ProtectionSettings.from_json(item)
        [route, settings]
      }.to_h

      new(data)
    end

    def initialize(data = {})
      @endpoints = data
      @endpoints.default = RuntimeSettings::ProtectionSettings.none
    end

    # @param route [Aikido::Zen::Route]
    # @return [Aikido::Zen::RuntimeSettings::ProtectionSettings]
    def [](route)
      @endpoints[route]
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
