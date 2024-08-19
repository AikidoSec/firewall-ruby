# frozen_string_literal: true

module Aikido::Agent
  # An individual user input in a request, which may come from different
  # sources (query string, body, cookies, etc).
  class Payload
    attr_reader :value, :source, :path

    def initialize(value, source, path)
      @value = value
      @source = source
      @path = path
    end

    alias_method :to_s, :value

    def ==(other)
      other.is_a?(Payload) && other.value == value && other.source == source
    end

    def inspect
      val = (value.to_s.size > 128) ? value[0..125] + "..." : value
      "#<Aikido::Agent::Payload #{source}(#{path}) #{val.inspect}>"
    end
  end
end
