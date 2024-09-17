# frozen_string_literal: true

require "rails"
require "action_controller"
require "action_dispatch/middleware/cookies"

module Test
  class Application < Rails::Application
  end
end

# This is a hackish little bit to be able to test a request going through the
# Rails router (to get the env modified with things like parameter parsing),
# without having to define a full-on application.
class MockedRailsRouter
  def self.build(&block)
    ActionDispatch::Routing::Mapper.stub_const(:Mapping, MockedRailsRouter::Mapping) do
      routes = ActionDispatch::Routing::RouteSet.new
      routes.draw { instance_exec(&block) }

      # Define classes for every controller so the app doesn't raise when trying
      # to find a class to process the requests.
      routes.set
        .map { |route| route.defaults[:controller].to_s.camelize << "Controller" }.uniq
        .reject { |name| MockedRailsRouter.const_defined?(name) }
        .each { |name| MockedRailsRouter.const_set(name, Class.new(ActionController::Base)) }

      Wrapper.new(routes)
    end
  end

  class Mapping < ActionDispatch::Routing::Mapper::Mapping
    def app(*)
      MockedRailsRouter.new
    end
  end

  Wrapper = Struct.new(:app) do
    def process(env)
      *, modified_env = app.call(env)
      modified_env
    end
  end

  def serve(request)
    [200, {}, request.env]
  end
end
