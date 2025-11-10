# frozen_string_literal: true

module Aikido::Zen
  # Routes keep information about the mapping defined in the current web
  # framework to go from a given HTTP request to the code that handles said
  # request.
  class Route
    def self.from_json(data)
      new(
        verb: data[:method],
        path: data[:path]
      )
    end

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

    # Sort routes by wildcard matching order deterministically:
    #
    #   1. Exact path before wildcard path
    #   2. Fewer wildcards in path relative to path length
    #   3. Earliest wildcard position in path
    #   4. Exact verb before wildcard verb
    #   5. Lexicographic path (tie-break)
    #   6. Lexicographic verb (tie-break)
    #
    # @return [Array] the sort key
    def sort_key
      @sort_key ||= begin
        stars = []
        i = -1
        while (i = path.index("*", i + 1))
          stars << i
        end

        [
          stars.empty? ? 0 : 1,
          stars.length - path.length,
          stars,
          (verb == "*") ? 1 : 0,
          path,
          verb
        ].freeze
      end
    end

    def match?(other)
      other.is_a?(Route) &&
        pattern(verb).match?(other.verb) &&
        pattern(path).match?(other.path)
    end

    def inspect
      "#<#{self.class.name} #{verb} #{path.inspect}>"
    end

    # Construct a regular expression equivalent to the wildcard string,
    # where '*' is the wildcard operator.
    #
    # The resulting pattern matches the entire input, allows an optional
    # trailing slash, and is case-insensitive.
    #
    # All other special characters in the regular expression are escaped
    # so that they are treated literally.
    #
    # @param string [String] wildcard string
    # @return [Regexp] regular expression matching the wildcard string
    private def pattern(string)
      /^#{Regexp.escape(string).gsub("\\*", ".*")}\/?$/i
    end
  end
end
