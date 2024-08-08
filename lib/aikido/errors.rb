# frozen_string_literal: true

module Aikido
  # Support rescuing Aikido::Error without forcing a single base class to all
  # errors (so things that should be e.g. a TypeError, can have the correct
  # superclass).
  module Error; end

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
