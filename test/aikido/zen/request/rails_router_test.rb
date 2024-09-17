# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Request::RailsRouterTest < ActiveSupport::TestCase
  setup do
    @routes = ActionDispatch::Routing::RouteSet.new
    @router = Aikido::Zen::Request::RailsRouter.new(@routes)
  end

  def assert_recognizes(verb, path, from:)
    route = @router.recognize(from)
    refute_nil route, "expected #{from.inspect} to be recognized as #{verb} #{path}. Available routes are:\n\n#{inspect_routes}\n"
    assert_equal verb, route.verb
    assert_equal path, route.path
  end

  def refute_recognizes(request)
    route = @router.recognize(request)
    assert_nil route, "expected #{request.inspect} to not be recognized. Available routes are:\n\n#{inspect_routes}\n"
  end

  test "returns nil if no routes are defined" do
    @routes.draw {}

    refute_recognizes(build_request("/test"))
  end

  test "recognizes the root route" do
    @routes.draw do
      root to: "pages#index"
    end

    assert_recognizes "GET", "/", from: build_request("/")
  end

  test "recognizes a route defined explicitly" do
    @routes.draw do
      get "/foo" => "foo#bar"
    end

    assert_recognizes "GET", "/foo(.:format)", from: build_request("/foo")
  end

  test "recognizes the appropriate route when multiple verbs match a given path" do
    @routes.draw do
      match "/foo" => "foo#bar", :via => [:get, :post]
    end

    assert_recognizes "GET", "/foo(.:format)", from: build_request("/foo")
    assert_recognizes "POST", "/foo(.:format)", from: build_request(
      "/foo", "REQUEST_METHOD" => "POST"
    )
  end

  test "recognizes routes with parameters" do
    @routes.draw do
      get "/profile/:username", to: "users#show"
    end

    req = build_request("/profile/jane.doe")
    assert_recognizes "GET", "/profile/:username(.:format)", from: req
  end

  test "recognizes routes with optional segments" do
    @routes.draw do
      get "/users/:id(/profile)", to: "users#show"
    end

    prefix_req = build_request("/users/123")
    assert_recognizes "GET", "/users/:id(/profile)(.:format)", from: prefix_req

    full_req = build_request("/users/123/profile")
    assert_recognizes "GET", "/users/:id(/profile)(.:format)", from: full_req
  end

  test "recognizes routes with extra parameters" do
    @routes.draw do
      get "/foo", to: "foo#bar"
    end

    assert_recognizes "GET", "/foo(.:format)", from: build_request("/foo.json")
  end

  test "ignores query string when recognizing routes" do
    @routes.draw do
      get "/foo/:id", to: "foo#bar"
      get "/foo", to: "foo#baz"
    end

    assert_recognizes "GET", "/foo(.:format)", from: build_request("/foo?id=1")
  end

  test "recognizes resources routes" do
    @routes.draw do
      resources :cats
    end

    assert_recognizes "GET", "/cats(.:format)",
      from: build_request("/cats")
    assert_recognizes "GET", "/cats/:id(.:format)",
      from: build_request("/cats/123")
    assert_recognizes "GET", "/cats/new(.:format)",
      from: build_request("/cats/new")
    assert_recognizes "POST", "/cats(.:format)",
      from: build_request("/cats", "REQUEST_METHOD" => "POST")
    assert_recognizes "GET", "/cats/:id/edit(.:format)",
      from: build_request("/cats/123/edit")
    assert_recognizes "PATCH", "/cats/:id(.:format)",
      from: build_request("/cats/123", "REQUEST_METHOD" => "PATCH")
    assert_recognizes "PUT", "/cats/:id(.:format)",
      from: build_request("/cats/123", "REQUEST_METHOD" => "PUT")
    assert_recognizes "DELETE", "/cats/:id(.:format)",
      from: build_request("/cats/123", "REQUEST_METHOD" => "DELETE")
  end

  test "recognizes resource routes with overridden param names" do
    @routes.draw do
      resources :cats, param: :name
    end

    assert_recognizes "GET", "/cats/:name(.:format)",
      from: build_request("/cats/feline-dion")
  end

  test "recognizes singular resource routes" do
    @routes.draw do
      resource :cat
    end

    assert_recognizes "GET", "/cat(.:format)", from: build_request("/cat")
  end

  test "recognizes nested resource routes" do
    @routes.draw do
      resources :cats do
        resources :toys
      end
    end

    assert_recognizes "GET", "/cats/:cat_id/toys/:id(.:format)",
      from: build_request("/cats/123/toys/324")
  end

  test "recognizes shallow-nested routes" do
    @routes.draw do
      resources :cats do
        resources :toys, shallow: true
      end
    end

    assert_recognizes "GET", "/cats/:cat_id/toys(.:format)",
      from: build_request("/cats/123/toys")
    assert_recognizes "POST", "/cats/:cat_id/toys(.:format)",
      from: build_request("/cats/123/toys", "REQUEST_METHOD" => "POST")
    assert_recognizes "GET", "/cats/:cat_id/toys/new(.:format)",
      from: build_request("/cats/123/toys/new")
    assert_recognizes "GET", "/toys/:id(.:format)",
      from: build_request("/toys/324")
    assert_recognizes "GET", "/toys/:id/edit(.:format)",
      from: build_request("/toys/324/edit")
    assert_recognizes "PATCH", "/toys/:id(.:format)",
      from: build_request("/toys/324", "REQUEST_METHOD" => "PATCH")
    assert_recognizes "PUT", "/toys/:id(.:format)",
      from: build_request("/toys/324", "REQUEST_METHOD" => "PUT")
    assert_recognizes "DELETE", "/toys/:id(.:format)",
      from: build_request("/toys/324", "REQUEST_METHOD" => "DELETE")
  end

  test "recognizes namespaced routes" do
    @routes.draw do
      namespace :admin do
        resources :cats
      end
    end

    assert_recognizes "GET", "/admin/cats/:id(.:format)",
      from: build_request("/admin/cats/123")
  end

  test "recognizes scoped routes without a URL prefix" do
    @routes.draw do
      scope module: "admin" do
        resources :cats
      end
    end

    assert_recognizes "GET", "/cats/:id(.:format)",
      from: build_request("/cats/123")
  end

  test "recognizes routes scoped to a prefix but no class namespace" do
    @routes.draw do
      scope "/admin" do
        resources :cats
      end
    end

    assert_recognizes "GET", "/admin/cats/:id(.:format)",
      from: build_request("/admin/cats/123")
  end

  test "recognizes routes with parameterized prefixes" do
    @routes.draw do
      scope ":lang" do
        resources :cats
      end
    end

    assert_recognizes "GET", "/:lang/cats/:id(.:format)",
      from: build_request("/fr/cats/feline-dion")
  end

  test "recognizes routes that use concerns" do
    @routes.draw do
      concern :commentable do
        resources :comments, only: [:index, :create]
      end

      resources :posts, concerns: :commentable, only: [:index, :show]
    end

    assert_recognizes "GET", "/posts/:post_id/comments(.:format)",
      from: build_request("/posts/123/comments")
    assert_recognizes "POST", "/posts/:post_id/comments(.:format)",
      from: build_request("/posts/123/comments", "REQUEST_METHOD" => "POST")
  end

  test "recognizes member routes added to a resource" do
    @routes.draw do
      resources :cats do
        post :feed, on: :member
      end
    end

    assert_recognizes "POST", "/cats/:id/feed(.:format)",
      from: build_request("/cats/feline-dion/feed", "REQUEST_METHOD" => "POST")
  end

  test "recognizes collection routes added to a resource" do
    @routes.draw do
      resources :cats do
        post :feed, on: :collection
      end
    end

    assert_recognizes "POST", "/cats/feed(.:format)",
      from: build_request("/cats/feed", "REQUEST_METHOD" => "POST")
  end

  test "recognizes additional new routes added to a resource" do
    @routes.draw do
      resources :cats do
        get :preview, on: :new
      end
    end

    assert_recognizes "GET", "/cats/new/preview(.:format)",
      from: build_request("/cats/new/preview")
  end

  test "recognizes routes with segment constraints" do
    @routes.draw do
      resources :cats, constraints: {id: /\d+/}
    end

    assert_recognizes "GET", "/cats(.:format)", from: build_request("/cats")
    assert_recognizes "GET", "/cats/:id(.:format)", from: build_request("/cats/123")
    refute_recognizes build_request("/cats/feline-dion")
  end

  test "recognizes routes with request constraints" do
    @routes.draw do
      resources :cats, constraints: {subdomain: "admin"}
    end

    assert_recognizes "GET", "/cats(.:format)",
      from: build_request("/cats", "HTTP_HOST" => "admin.example.org")
  end

  test "is able to differentiate routes that only differ by constraints" do
    skip <<~TXT.squish
      We currently only support matching routes to a verb and path, and cannot
      differentiate between routes that solely match by a constraint.
    TXT

    @routes.draw do
      resources :cats, constraints: {subdomain: "admin"}
      resources :cats, constraints: {subdomain: "app"}
    end
  end

  test "recognizes routes that use globbing" do
    @routes.draw do
      get "/blog/*date", to: "posts#index"
    end

    assert_recognizes "GET", "/blog/*date(.:format)",
      from: build_request("/blog/2024")
    assert_recognizes "GET", "/blog/*date(.:format)",
      from: build_request("/blog/2024/08")
    assert_recognizes "GET", "/blog/*date(.:format)",
      from: build_request("/blog/2024/08/27")
  end

  test "recognizes redirects" do
    @routes.draw do
      get "/blog/:article" => redirect("/stories/%{article}")
    end

    assert_recognizes "GET", "/blog/:article(.:format)",
      from: build_request("/blog/for-sale-baby-shoes-never-worn")
  end

  SampleRackApp = ->(env) { [200, {}, "OK"] }

  test "recognizes routes matching a rack app" do
    @routes.draw do
      match "/admin", to: SampleRackApp, via: :all
    end

    assert_recognizes "GET", "/admin(.:format)", from: build_request("/admin")
    refute_recognizes build_request("/admin/path") # only matches explicit endpoint
  end

  test "recognizes routes to mounted rack apps" do
    @routes.draw do
      mount SampleRackApp, at: "/admin"
    end

    assert_recognizes "GET", "/admin", from: build_request("/admin")
    assert_recognizes "GET", "/admin", from: build_request("/admin/path")
  end

  test "recognizes routes to rack apps mounted in a parametric path" do
    @routes.draw do
      mount SampleRackApp, at: "/:lang/handler"
    end

    assert_recognizes "GET", "/:lang/handler", from: build_request("/en/handler")
    assert_recognizes "GET", "/:lang/handler", from: build_request("/en/handler/path")
  end

  class SampleEngine < ::Rails::Engine
    routes.draw do
      root to: "sample#test"
      get "/:sample" => "sample#test"
    end
  end

  test "recognizes routes to mounted engines" do
    @routes.draw do
      mount SampleEngine, at: "/base"
    end

    assert_recognizes "GET", "/base",
      from: build_request("/base")
    assert_recognizes "GET", "/base/:sample(.:format)",
      from: build_request("/base/hello-world")
  end

  test "recognizes routes to engines mounted in a parametric path" do
    @routes.draw do
      mount SampleEngine, at: "/:lang/samples"
    end

    assert_recognizes "GET", "/:lang/samples/:sample(.:format)",
      from: build_request("/es/samples/hola-mundo")
  end

  def build_request(path, env = {})
    env = Rack::MockRequest.env_for(path, env)
    env = Rails.application.env_config.merge(env)
    req = ActionDispatch::Request.new(env)
    Aikido::Zen::Request.new(req, framework: "rails", router: Object.new)
  end

  def inspect_routes(routes = @routes)
    inspector = ActionDispatch::Routing::RoutesInspector.new(routes.routes)
    formatter = ActionDispatch::Routing::ConsoleFormatter::Sheet.new
    inspector.format(formatter)
  end
end
