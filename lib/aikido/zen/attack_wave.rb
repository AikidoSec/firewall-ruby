# frozen_string_literal: true

require_relative "cache"
require_relative "attack_wave/helpers"

module Aikido::Zen
  module AttackWave
    class Detector
      # @return [Aikido::Zen::CappedSet]
      attr_reader :samples

      def initialize(config: Aikido::Zen.config, clock: nil)
        @config = config

        @event_times = Cache.new(@config.attack_wave_max_cache_entries, ttl: @config.attack_wave_min_time_between_events, clock: clock)

        @request_counts = Cache.new(@config.attack_wave_max_cache_entries, 0, ttl: @config.attack_wave_min_time_between_requests, clock: clock)

        @samples = Cache.new(@config.attack_wave_max_cache_samples, ttl: @config.attack_wave_min_time_between_requests, clock: clock) { CappedSet.new(15) }
      end

      def attack_wave?(context)
        client_ip = context.request.client_ip

        return false unless client_ip

        return false if @event_times[client_ip]

        return false unless AttackWave::Helpers.web_scanner?(context)

        request_count = @request_counts[client_ip] += 1

        context.request.then do |request|
          @samples[client_ip] <<= Sample.new(
            verb: request.request_method,
            path: request.fullpath
          )
        end

        return false if request_count < @config.attack_wave_threshold

        @event_times[client_ip] = Time.now.utc

        true
      end
    end

    class Request
      # @return [String]
      attr_reader :ip_address

      # @return [String]
      attr_reader :user_agent

      # @return [String]
      attr_reader :source

      # @param ip_address [String]
      # @param user_agent [String]
      # @param source [String]
      # @return [Aikido::Zen::AttackWave::Request]
      def initialize(ip_address:, user_agent:, source:)
        @ip_address = ip_address
        @user_agent = user_agent
        @source = source
      end

      def as_json
        {
          ipAddress: @ip_address,
          userAgent: @user_agent,
          source: @source
        }.compact
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.ip_address == ip_address &&
          other.user_agent == user_agent &&
          other.source == source
      end
      alias_method :eql?, :==
    end

    class Attack
      # @return [Aikido::Zen::AttackWave::Sample]
      attr_reader :samples

      # @return [Aikido::Zen::Actor]
      attr_reader :user

      # @param samples [Aikido::Zen::AttackWave::Sample]
      # @param user [Aikido::Zen::Actor]
      # @return [Aikido::Zen::AttackWave::Attack]
      def initialize(samples:, user:)
        @samples = samples
        @user = user
      end

      def as_json
        {
          metadata: {
            samples: @samples.as_json.to_json # The API only accepts string values in metadata
          },
          user: @user.as_json
        }.compact
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.samples == samples &&
          other.user == user
      end
      alias_method :eql?, :==
    end

    class Sample
      # @return [String]
      attr_reader :verb

      # @return [String]
      attr_reader :path

      def initialize(verb:, path:)
        @verb = verb
        @path = path
      end

      def as_json
        {
          method: @verb.as_json,
          url: @path.as_json
        }.compact
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.verb == verb &&
          other.path == path
      end
      alias_method :eql?, :==

      def hash
        [verb, path].hash
      end
    end
  end
end
