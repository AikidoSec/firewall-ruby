# frozen_string_literal: true

module Aikido::Zen
  # Routes keep information about the mapping defined in the current web
  # framework to go from a given HTTP request to the code that handles said
  # request.
  class Route
    # @return [String] the HTTP verb used to request this route.
    attr_reader :verb

    # @return [String] the URL pattern used to match request paths. For
    #   example "/users/:id".
    attr_reader :path

    def initialize(verb:, path:)
      @verb = verb
      @path = path
    end

    def as_json
      {method: verb, path: path}
    end

    def ==(other)
      other.is_a?(Route) &&
        other.verb == verb &&
        other.path == path
    end
    alias_method :eql?, :==

    def hash
      [verb, path].hash
    end

    def inspect
      "#<#{self.class.name} #{verb} #{path.inspect}>"
    end
  end
end
