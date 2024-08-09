# frozen_string_literal: true

module Aikido
  # Support rescuing Aikido::Error without forcing a single base class to all
  # errors (so things that should be e.g. a TypeError, can have the correct
  # superclass).
  module Error; end

  # Generic error for problems with the Agent.
  class AgentError < RuntimeError
    include Error
  end

  module Agent
    # Wrapper for all low-level network errors communicating with the API. You
    # can access the original error by calling #cause.
    class NetworkError < StandardError
      include Error
    end

    # Raised whenever a request to the API results in a 4XX or 5XX response.
    class APIError < StandardError
      include Error

      attr_reader :request
      attr_reader :response

      def initialize(request, response)
        @request = anonimize_token(request.dup)
        @response = response

        super("Error in #{request.method} #{request.path}: #{response.code} #{response.message} (#{response.body})")
      end

      private def anonimize_token(request)
        # Anonimize the token to `********************xxxx`,
        # mimicking what we show in the dashbaord.
        request["Authorization"] = request["Authorization"].to_s
          .gsub(/\A.*(.{4})\z/, ("*" * 20) + "\\1")
        request
      end
    end
  end

  module Firewall
    class SQLInjectionError < StandardError
      include Error

      attr_reader :query
      attr_reader :input
      attr_reader :dialect

      def initialize(query, input, dialect)
        super("SQL injection detected! User input <#{input}> not escaped in #{dialect} query: <#{query}>")
        @query = query
        @input = input
        @dialect = dialect
      end
    end
  end
end
