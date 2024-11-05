# frozen_string_literal: true

require_relative "../capped_collections"

module Aikido::Zen
  # @api private
  #
  # Keeps track of the hostnames to which the app has made outbound HTTP
  # requests.
  class Collector::Hosts < Aikido::Zen::CappedSet
    def initialize(config = Aikido::Zen.config)
      super(config.max_outbound_connections)
    end
  end
end
