# frozen_string_literal: true

module Aikido::Zen
  # Simple data object to identify connections performed to outbound servers.
  class OutboundConnection
    def self.from_json(data)
      new(
        host: data[:hostname],
        port: data[:port]
      )
    end

    # Convenience factory to create connection descriptions out of URI objects.
    #
    # @param uri [URI]
    # @return [Aikido::Zen::OutboundConnection]
    def self.from_uri(uri)
      new(host: uri.hostname, port: uri.port)
    end

    # @return [String] the hostname or IP address to which the connection was
    #   attempted.
    attr_reader :host

    # @return [Integer] the port number to which the connection was attempted.
    attr_reader :port

    # @return [Integer] the number of times that this connection was seen by
    #   the hosts collector.
    attr_reader :hits

    def initialize(host:, port:)
      @host = host
      @port = port
    end

    def hit
      # Lazy initialize @hits, so it stays nil until the connection is tracked.
      @hits ||= 0
      @hits += 1
    end

    def as_json
      {hostname: host, port: port, hits: hits}.compact
    end

    def ==(other)
      other.is_a?(OutboundConnection) &&
        host == other.host &&
        port == other.port
    end
    alias_method :eql?, :==

    def hash
      [host, port].hash
    end

    def inspect
      "#<#{self.class.name} #{host}:#{port}>"
    end
  end
end
