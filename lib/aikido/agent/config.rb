# frozen_string_literal: true

require "uri"

module Aikido::Agent
  class Config
    # @return [URI] The HTTP host for the Aikido API. Defaults to
    #   +https://guard.aikido.dev+.
    attr_reader :api_base_url

    # @return [Hash] HTTP timeouts for communicating with the API.
    attr_reader :api_timeouts

    # @return [String] the token obtained when configuring the Firewall in the
    #   Aikido interface.
    attr_accessor :api_token

    def initialize
      self.api_timeouts = 10
      self.api_base_url = ENV.fetch("AIKIDO_BASE_URL", DEFAULT_API_BASE_URL)
      self.api_token = ENV.fetch("AIKIDO_TOKEN", nil)
    end

    # Set the base URL for API requests.
    #
    # @param url [String, URI]
    def api_base_url=(url)
      @api_base_url = URI(url)
    end

    # @overload def api_timeouts=(timeouts)
    #   Configure granular connection timeouts for the Aikido Firewall API. You
    #   can set any of these per call.
    #   @param timeouts [Hash]
    #   @option timeouts [Integer] :open_timeout Duration in seconds.
    #   @option timeouts [Integer] :read_timeout Duration in seconds.
    #   @option timeouts [Integer] :write_timeout Duration in seconds.
    #
    # @overload def api_timeouts=(duration)
    #   Configure the connection timeouts for the Aikido Firewall API.
    #   @param duration [Integer] Duration in seconds to set for all three
    #     timeouts (open, read, and write).
    def api_timeouts=(value)
      value = {open_timeout: value, read_timeout: value, write_timeout: value} if value.respond_to?(:to_int)

      @api_timeouts ||= {}
      @api_timeouts.update(value)
    end

    # @!visibility private
    DEFAULT_API_BASE_URL = "https://guard.aikido.dev"
  end
end
