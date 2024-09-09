# frozen_string_literal: true

require "ipaddr"
require_relative "../route"
require_relative "../request"

module Aikido::Zen
  # Simple router implementation that just identifies the currently requested
  # URL as a route, attempting to heuristically substitute any path segments
  # that may look like a parameterized value by something descriptive.
  #
  # For example, "/categories/123/events/2024-10-01" would be matched as
  # "/categories/:number/events/:date"
  class Request::HeuristicRouter
    # @param request [Aikido::Zen::Request]
    # @return [Aikido::Zen::Route, nil]
    def recognize(request)
      path = parameterize(request.path)
      Route.new(verb: request.request_method, path: path)
    end

    private def parameterize(path)
      return if path.nil?

      path = path.split("/").map { |part| parameterize_segment(part) }.join("/")
      path.prepend("/") unless path.start_with?("/")
      path.chomp!("/") if path.size > 1
      path
    end

    private def parameterize_segment(segment)
      case segment
      when NUMBER
        ":number"
      when UUID
        ":uuid"
      when DATE
        ":date"
      when EMAIL
        ":email"
      when IP
        ":ip"
      when HASH
        ":hash"
      when SecretMatcher
        ":secret"
      else
        segment
      end
    end

    NUMBER = /\A\d+\z/
    HEX = /\A[a-f0-9]+\z/i
    DATE = /\A\d{4}-\d{2}-\d{2}|\d{2}-\d{2}-\d{4}\z/
    UUID = /\A
            (?:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}
            | 00000000-0000-0000-0000-000000000000
            | ffffffff-ffff-ffff-ffff-ffffffffffff
            )\z/ix
    EMAIL = /\A
              [a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+
              @
              [a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
              (?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*
            \z/x
    IP = ->(segment) {
      IPAddr::RE_IPV4ADDRLIKE.match?(segment) ||
        IPAddr::RE_IPV6ADDRLIKE_COMPRESSED.match?(segment) ||
        IPAddr::RE_IPV6ADDRLIKE_FULL.match?(segment)
    }
    HASH = ->(segment) { [32, 40, 64, 128].include?(segment.size) && HEX === segment }

    class SecretMatcher
      # Decides if a given string looks random enough to be a "secret".
      #
      # @param candidate [String]
      # @return [Boolean]
      def self.===(candidate)
        new(candidate).matches?
      end

      private def initialize(string)
        @string = string
      end

      def matches?
        return false if @string.size <= MIN_LENGTH
        return false if SEPARATORS === @string
        return false unless DIGIT === @string
        return false if [LOWER, UPPER, SPECIAL].none? { |pattern| pattern === @string }

        ratios = @string.chars.each_cons(MIN_LENGTH).map do |window|
          window.to_set.size / MIN_LENGTH.to_f
        end

        ratios.sum / ratios.size > SECRET_THRESHOLD
      end

      MIN_LENGTH = 10
      SECRET_THRESHOLD = 0.75

      LOWER = /[[:lower:]]/
      UPPER = /[[:upper:]]/
      DIGIT = /[[:digit:]]/
      SPECIAL = /[!#\$%^&*|;:<>]/
      SEPARATORS = /[[:space:]]|-/
    end
  end
end
