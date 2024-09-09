# frozen_string_literal: true

module Aikido::Zen
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
      other.is_a?(Payload) &&
        other.value == value &&
        other.source == source &&
        other.path == path
    end

    def as_json
      {
        payload: value.to_s,
        source: SOURCE_SERIALIZATIONS[source],
        pathToPayload: path.to_s
      }
    end

    SOURCE_SERIALIZATIONS = {
      query: "query",
      body: "body",
      header: "headers",
      cookie: "cookies",
      route: "routeParams",
      graphql: "graphql",
      xml: "xml",
      subdomain: "subdomains"
    }

    def inspect
      val = (value.to_s.size > 128) ? value[0..125] + "..." : value
      "#<Aikido::Zen::Payload #{source}(#{path}) #{val.inspect}>"
    end
  end
end
