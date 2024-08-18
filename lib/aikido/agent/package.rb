# frozen_string_literal: true

require_relative "../firewall/sink"

module Aikido::Agent
  Package = Struct.new(:name, :version) do
    def initialize(name, version, sinks = Aikido::Firewall::Sinks.registry)
      super(name, version)
      @sinks = sinks
    end

    # @return [Boolean] whether we explicitly protect against exploits in this
    #   library.
    def supported?
      @sinks.include?(name)
    end

    def as_json
      {name => version.to_s}
    end
  end
end
