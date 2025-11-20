# frozen_string_literal: true

require_relative "cache"
require_relative "attack_wave/helpers"

module Aikido::Zen
  module AttackWave
    class Detector
      def initialize(config: Aikido::Zen.config, clock: nil)
        @config = config

        @event_times = Cache.new(@config.attack_wave_max_cache_entries, ttl: @config.attack_wave_min_time_between_events, clock: clock)

        @request_counts = Cache.new(@config.attack_wave_max_cache_entries, 0, ttl: @config.attack_wave_min_time_between_requests, clock: clock)
      end

      def attack_wave?(context)
        client_ip = context.request.client_ip

        return false unless client_ip

        return false if @event_times[client_ip]

        return false unless AttackWave::Helpers.web_scanner?(context)

        request_count = @request_counts[client_ip] += 1

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
    end

    class Attack
      # @return [Hash<String, String>]
      attr_reader :metadata

      # @return [Aikido::Zen::Actor]
      attr_reader :user

      # @param metadata [Hash<String, String>]
      # @param metadata [Aikido::Zen::Actor]
      # @return [Aikido::Zen::AttackWave::Attack]
      def initialize(metadata:, user:)
        @metadata = metadata
        @user = user
      end

      def as_json
        {
          metadata: @metadata.as_json,
          user: @user.as_json
        }.compact
      end
    end
  end
end
