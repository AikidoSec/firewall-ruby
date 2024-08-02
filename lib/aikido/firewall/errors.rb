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

    def initialize(query, input)
      super("SQL injection detected! User input <#{input}> not escaped in query: <#{query}>")
      @query = query
      @input = input
    end
  end
end
