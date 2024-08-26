# frozen_string_literal: true

require "delegate"

module Aikido::Agent
  # Wrapper around Rack::Request-like objects to add some behavior.
  class Request < SimpleDelegator
    # @return [String] identifier of the framework handling this HTTP request.
    attr_reader :framework

    def initialize(delegate, framework:)
      super(delegate)
      @framework = framework
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

    # @return [String] the request body, up to a maximum of 16KiB. If the
    #   underlying IO object had been partially (or fully) read before,
    #   this will restore the previous cursor position after reading it.
    def truncated_body(max_size: 16384)
      return @truncated_body if defined?(@truncated_body)
      return nil if body.nil?

      begin
        initial_pos = body.pos
        body.rewind
        @truncated_body = body.read(max_size)
      ensure
        body.rewind
        body.seek(initial_pos)
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
        route: nil
      }
    end

    BLESSED_CGI_HEADERS = %w[CONTENT_TYPE CONTENT_LENGTH]
  end
end
