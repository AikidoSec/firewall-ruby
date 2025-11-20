# frozen_string_literal: true

require "delegate"

module Aikido::Zen
  # Wrapper around Rack::Request-like objects to add some behavior.
  class Request < SimpleDelegator
    # @return [String] identifier of the framework handling this HTTP request.
    attr_reader :framework

    # @return [Aikido::Zen::Router]
    attr_reader :router

    # The current user, if set by the host app.
    #
    # @return [Aikido::Zen::Actor, nil]
    # @see Aikido::Zen.track_user
    attr_accessor :actor

    def initialize(delegate, config = Aikido::Zen.config, framework:, router:)
      super(delegate)
      @config = config
      @framework = framework
      @router = router
    end

    def __setobj__(delegate) # :nodoc:
      super
      @route = @normalized_header = nil
    end

    # @return [Aikido::Zen::Route] the framework route being requested.
    def route
      @route ||= @router.recognize(self)
    end

    # @return [Aikido::Zen::Request::Schema, nil]
    def schema
      @schema ||= Aikido::Zen::Request::Schema.build
    end

    # @return [String] the IP address of the client making the request.
    def client_ip
      return @client_ip if @client_ip

      if @config.client_ip_header
        value = env[@config.client_ip_header]
        if Resolv::AddressRegex.match?(value)
          @client_ip = value
        else
          @config.logger.warn("Invalid IP address in custom client IP header `#{@config.client_ip_header}`: `#{value}`")
        end
      end

      @client_ip ||= respond_to?(:remote_ip) ? remote_ip : ip
    end

    # Map the CGI-style env Hash into "pretty-looking" headers, preserving the
    # values as-is. For example, HTTP_ACCEPT turns into "Accept", CONTENT_TYPE
    # turns into "Content-Type", and HTTP_X_FORWARDED_FOR turns into
    # "X-Forwarded-For".
    #
    # @return [Hash<String, String>]
    def normalized_headers
      @normalized_headers ||= env.slice(*BLESSED_CGI_HEADERS)
        .merge(env.select { |key, _| key.start_with?("HTTP_") })
        .transform_keys { |header|
          name = header.sub(/^HTTP_/, "").downcase
          name.split("_").map { |part| part[0].upcase + part[1..] }.join("-")
        }
    end

    def as_json
      {
        method: request_method.downcase,
        url: url,
        ipAddress: client_ip,
        userAgent: user_agent,
        source: framework,
        route: route&.path
      }
    end

    BLESSED_CGI_HEADERS = %w[CONTENT_TYPE CONTENT_LENGTH]
  end
end

require_relative "request/schema"
