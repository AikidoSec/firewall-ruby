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

    def initialize(delegate, framework:, router:)
      super(delegate)
      @framework = framework
      @router = router
      @body_read = false
    end

    def __setobj__(delegate) # :nodoc:
      super
      @body_read = false
      @route = @normalized_header = @truncated_body = nil
    end

    # @return [Aikido::Zen::Route] the framework route being requested.
    def route
      @route ||= @router.recognize(self)
    end

    # @return [Aikido::Zen::Request::Schema, nil]
    def schema
      @schema ||= Aikido::Zen::Request::Schema.build
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

    # @api private
    #
    # Reads the first 16KiB of the request body, to include in attack reports
    # back to the Aikido server. This method should only be called if an attack
    # is detected during the current request.
    #
    # If the underlying IO object has been partially (or fully) read before,
    # this will attempt to restore the previous cursor position after reading it
    # if possible, or leave if rewund if not.
    #
    # @param max_size [Integer] number of bytes to read at most.
    #
    # @return [String]
    def truncated_body(max_size: 16384)
      return @truncated_body if @body_read
      return nil if body.nil?

      begin
        initial_pos = body.pos if body.respond_to?(:pos)
        body.rewind
        @truncated_body = body.read(max_size)
      ensure
        @body_read = true
        body.rewind
        body.seek(initial_pos) if initial_pos && body.respond_to?(:seek)
      end
    end

    def as_json
      {
        method: request_method.downcase,
        url: url,
        ipAddress: ip,
        userAgent: user_agent,
        headers: normalized_headers.reject { |_, val| val.to_s.empty? },
        body: truncated_body,
        source: framework,
        route: route&.path
      }
    end

    BLESSED_CGI_HEADERS = %w[CONTENT_TYPE CONTENT_LENGTH]
  end
end

require_relative "request/schema"
