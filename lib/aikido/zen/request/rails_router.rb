# frozen_string_literal: true

require_relative "../route"
require_relative "../request"

module Aikido::Zen
  # The Rails router relies on introspecting the routes defined in the Rails
  # app to match the current request to the correct route, building Route
  # objects that have the exact pattern defined by the developer, rather than
  # a heuristic approximation.
  #
  # For example, given the following route definitions:
  #
  #   resources :posts do
  #     resources :comments
  #   end
  #
  # The router will map a request to "/posts/123/comments/234" to
  # "/posts/:post_id/comments/:id(.:format)".
  #
  # @see Aikido::Zen::Router::HeuristicRouter
  class Request::RailsRouter
    def initialize(route_set)
      @route_set = route_set
    end

    def recognize(request)
      recognize_in_route_set(request, @route_set)
    end

    private def recognize_in_route_set(request, route_set, prefix: nil)
      route_set.router.recognize(request) do |route, _|
        app = route.app
        next unless app.matches?(request)

        if app.dispatcher?
          return build_route(route, request, prefix: prefix)
        end

        if app.engine?
          # If the SCRIPT_NAME has any path parameters, we want those to be
          # captured by the router. (eg `mount API => "/api/:version/`)
          prefix = ActionDispatch::Routing::RouteWrapper.new(route).path
          return recognize_in_route_set(request, app.rack_app.routes, prefix: prefix)
        end

        if app.rack_app.respond_to?(:redirect?) && app.rack_app.redirect?
          return build_route(route, request, prefix: prefix)
        end

        # At this point we're matching plain Rack apps, where Rails does not
        # remove the SCRIPT_NAME from PATH_INFO, so we should avoid adding
        # SCRIPT_NAME twice.
        return build_route(route, request, prefix: nil)
      end

      nil
    end

    private def build_route(route, request, prefix: request.script_name)
      Rails::Route.new(route, prefix: prefix, verb: request.request_method)
    end
  end

  module Rails
    class Route < Aikido::Zen::Route
      attr_reader :verb

      def initialize(rails_route, verb: rails_route.verb, prefix: nil)
        @route = ActionDispatch::Routing::RouteWrapper.new(rails_route)
        @verb = verb
        @prefix = prefix
      end

      def path
        if @prefix.present?
          File.join(@prefix.to_s, @route.path).chomp("/")
        else
          @route.path
        end
      end
    end
  end
end
