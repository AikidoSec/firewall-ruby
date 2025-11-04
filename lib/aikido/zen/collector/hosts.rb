# frozen_string_literal: true

require_relative "../capped_collections"

module Aikido::Zen
  # @api private
  #
  # Keeps track of the hostnames to which the app has made outbound HTTP
  # requests.
  class Collector::Hosts < Aikido::Zen::CappedMap
    def initialize(config = Aikido::Zen.config)
      super(config.max_outbound_connections)
    end

    # @param host [Aikido::Zen::OutboundConnection]
    # @return [void]
    def add(host)
      self[host] ||= host
      self[host].hit
    end

    def each(&blk)
      each_value(&blk)
    end

    def as_json
      map(&:as_json)
    end
  end
end
