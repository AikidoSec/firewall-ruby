# frozen_string_literal: true

module Aikido::Zen
  class APICache
    attr_reader :runtime_config
    attr_reader :runtime_firewall_lists
    attr_reader :runtime_config_generation
    attr_reader :runtime_firewall_lists_generation

    def initialize
      @runtime_config_generation = 0
      @runtime_firewall_lists_generation = 0
    end

    def runtime_config=(value)
      update_runtime_config(value)
    end

    def runtime_firewall_lists=(value)
      update_runtime_firewall_lists(value)
    end

    # @param value [Hash, nil]
    # @return [Boolean] whether the value actually changed
    def update_runtime_config(value)
      return false if value == @runtime_config

      @runtime_config_generation += 1
      @runtime_config = value

      true
    end

    # @param value [Hash, nil]
    # @return [Boolean] whether the value actually changed
    def update_runtime_firewall_lists(value)
      return false if value == @runtime_firewall_lists

      @runtime_firewall_lists_generation += 1
      @runtime_firewall_lists = value

      true
    end

    # @param known_generation [Integer, nil]
    # @return [Array(Object, Integer), nil] the current value and generation,
    #   or nil if the known generation is already current.
    def config_if_changed(known_generation)
      return nil if known_generation == runtime_config_generation
      [runtime_config, runtime_config_generation]
    end

    # @param known_generation [Integer, nil]
    # @return [Array(Object, Integer), nil] the current value and generation,
    #   or nil if the known generation is already current.
    def firewall_lists_if_changed(known_generation)
      return nil if known_generation == runtime_firewall_lists_generation
      [runtime_firewall_lists, runtime_firewall_lists_generation]
    end
  end
end
