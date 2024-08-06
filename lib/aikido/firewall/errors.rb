# frozen_string_literal: true

module Aikido::Firewall
  # Support rescuing Aikido::Firewall::Error without forcing a single base class
  # to all errors (so things that should be a e.g. TypeError can have the right
  # superclass).
  module Error; end

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
