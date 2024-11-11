# frozen_string_literal: true

require "forwardable"

module Aikido
  # @!visibility private
  # Support rescuing Aikido::Error without forcing a single base class to all
  # errors (so things that should be e.g. a TypeError, can have the correct
  # superclass).
  module Error; end # :nodoc:

  # @!visibility private
  # Generic error for problems with the Agent.
  class ZenError < RuntimeError
    include Error
  end

  module Zen
    # Wrapper for all low-level network errors communicating with the API. You
    # can access the original error by calling #cause.
    class NetworkError < StandardError
      include Error

      def initialize(request, cause = nil)
        @request = request.dup

        super("Error in #{request.method} #{request.path}: #{cause.message}")
      end
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

    # Raised whenever a response to the API results in a 429 response.
    class RateLimitedError < APIError; end

    class UnderAttackError < StandardError
      include Error

      attr_reader :attack

      def initialize(attack)
        super(attack.log_message)
        @attack = attack
      end
    end

    class SQLInjectionError < UnderAttackError
      extend Forwardable
      def_delegators :@attack, :query, :input, :dialect
    end

    class SSRFDetectedError < UnderAttackError
      extend Forwardable
      def_delegators :@attack, :request, :input
    end

    # Raised when there's any problem communicating (or loading) libzen.
    class InternalsError < ZenError
      # @param attempt [String] description of what we were trying to do.
      # @param problem [String] what couldn't be done.
      # @param libname [String] the name of the file (including the arch).
      def initialize(attempt, problem, libname)
        super(format(<<~MSG.chomp, attempt, problem, libname))
          Zen could not scan %s due to a problem %s the library `%s'
        MSG
      end
    end
  end
end
