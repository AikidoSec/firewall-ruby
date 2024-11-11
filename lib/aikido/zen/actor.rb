# frozen_string_literal: true

require "concurrent"
require_relative "config"

module Aikido::Zen
  # Converts an object into an Actor for reporting back to the Aikido Dashboard.
  #
  # @overload Actor(actor)
  #   @param actor [#to_aikido_actor] anything that implements #to_aikido_actor
  #     will have that method called and its value returned.
  #   @return Aikido::Zen::Actor
  #
  # @overload Actor(data)
  #   @param data [Hash<Symbol, String>]
  #   @option data [String] :id a unique identifier for this user.
  #   @option data [String, nil] :name an optional name to display in the UI.
  #   @return Aikido::Zen::Actor
  def self.Actor(data)
    return if data.nil?
    return data.to_aikido_actor if data.respond_to?(:to_aikido_actor)

    attrs = {}
    if data.respond_to?(:to_hash)
      attrs = data.to_hash
        .slice("id", "name", :id, :name)
        .compact
        .transform_keys(&:to_sym)
        .transform_values(&:to_s)
    else
      return nil
    end

    return nil if attrs[:id].nil? || attrs[:id].to_s.strip.empty?

    Actor.new(**attrs)
  end

  # Represents someone connecting to the application and making requests.
  class Actor
    # @return [String] a unique identifier for this user.
    attr_reader :id

    # @return [String, nil] an optional name to display in the Aikido UI.
    attr_reader :name

    # @return [Time]
    attr_reader :first_seen_at

    # @param id [String]
    # @param name [String, nil]
    # @param ip [String, nil]
    # @param seen_at [Time]
    def initialize(
      id:,
      name: nil,
      ip: Aikido::Zen.current_context&.request&.ip,
      seen_at: Time.now.utc
    )
      @id = id
      @name = name
      @first_seen_at = seen_at
      @last_seen_at = Concurrent::AtomicReference.new(seen_at)
      @ip = Concurrent::AtomicReference.new(ip)
    end

    # @return [Time]
    def last_seen_at
      @last_seen_at.get
    end

    # @return [String, nil] the IP address last used by this user, if available.
    def ip
      @ip.get
    end

    # Atomically update the last IP used by the user, and the last time they've
    # been "seen" connecting to the app.
    #
    # @param ip [String, nil] the last-seen IP address for the user. If +nil+
    #   and we had a non-empty value before, we won't update it. Defaults to
    #   the current HTTP request's IP address, if any.
    # @param seen_at [Time] the time at which we're making the update. We will
    #   always keep the most recent time if this conflicts with the current
    #   value.
    # @return [void]
    def update(seen_at: Time.now.utc, ip: Aikido::Zen.current_context&.request&.ip)
      @last_seen_at.try_update { |last_seen_at| [last_seen_at, seen_at].max }
      @ip.try_update { |last_ip| [ip, last_ip].compact.first }
    end

    # @return [self]
    def to_aikido_actor
      self
    end

    def ==(other)
      other.is_a?(Actor) && id == other.id
    end
    alias_method :eql?, :==

    def hash
      id.hash
    end

    def as_json
      {
        id: id,
        name: name,
        lastIpAddress: ip,
        firstSeenAt: first_seen_at.to_i * 1000,
        lastSeenAt: last_seen_at.to_i * 1000
      }.compact
    end
  end
end
