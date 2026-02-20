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
  #   block_request unless endpoint.allows?(request.client_ip)
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

    # Match the route against the endpoints, and return the first match.
    #
    # @param route [Aikido::Zen::Route] the route to match
    #
    # @yield [pattern, settings] the optional block to call when a match is found
    # @yieldparam pattern [Aikido::Zen::Route] the matched route
    # @yieldparam settings [Aikido::Zen::RuntimeSettings::ProtectionSettings] the associated protection settings
    # @yieldreturn Object
    #
    # @return [Array<Aikido::Zen::Route, Aikido::Zen::RuntimeSettings::ProtectionSettings>] the value if no block is given
    # @return [Object] the block return value if a block is given
    # @return [nil] if no match is found
    def match(route)
      if @endpoints.key?(route)
        if block_given?
          return yield(route, @endpoints[route])
        else
          return [route, @endpoints[route]]
        end
      end

      # Wildcard endpoint matching

      @endpoints.each do |pattern, settings|
        if pattern.match?(route)
          if block_given?
            return yield(pattern, settings)
          else
            return [pattern, settings]
          end
        end
      end

      nil
    end

    # Match the route against the endpoints, and return all matches.
    #
    # @param route [Aikido::Zen::Route] the route to match
    #
    # @yield [pattern, settings] the optional block to call when a match is found
    # @yieldparam pattern [Aikido::Zen::Route] the matched route
    # @yieldparam settings [Aikido::Zen::RuntimeSettings::ProtectionSettings] the associated protection settings
    # @yieldreturn Object
    #
    # @return [Array<Aikido::Zen::Route, Aikido::Zen::RuntimeSettings::ProtectionSettings>] the values if no block is given
    # @return [Array<Object>] the block return values if a block is given
    def matches(route)
      results = []

      @endpoints.each do |pattern, settings|
        if pattern.match?(route)
          results <<
            if block_given?
              yield(pattern, settings)
            else
              [pattern, settings]
            end
        end
      end

      results
    end

    # @param route [Aikido::Zen::Route]
    # @return [Aikido::Zen::RuntimeSettings::ProtectionSettings]
    def [](route)
      result = match(route) { |_pattern, settings| settings }
      result || @endpoints.default
    end

    # @param route [Aikido::Zen::Route]
    # @return [Array<Aikido::Zen::RuntimeSettings::ProtectionSettings>]
    def matched_settings(route)
      results = matches(route) { |_pattern, settings| settings }
      results << @endpoints.default if results.empty?
      results
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
