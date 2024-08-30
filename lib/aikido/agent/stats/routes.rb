# frozen_string_literal: true

class Aikido::Agent::Stats
  # @api private
  #
  # Keeps track of the visited routes.
  class Routes
    def initialize
      @routes = Hash.new(0)
    end

    # @param route [Aikido::Agent::Route, nil] tracks the visit, if given.
    def add(route)
      @routes[route] += 1 if route
    end

    # @!visibility private
    def [](route)
      @routes[route]
    end

    # @!visibility private
    def empty?
      @routes.empty?
    end

    def as_json
      @routes.map do |route, hits|
        route.as_json.merge(hits: hits)
      end
    end
  end
end
