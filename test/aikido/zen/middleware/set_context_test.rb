# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::SetContextText < ActiveSupport::TestCase
  setup do
    @contexts = []
    app = ->(env) { @downstream.call(env) }
    @middleware = Aikido::Zen::Middleware::SetContext.new(app)
    @downstream = ->(env) { @contexts << env }
  end

  test "makes Zen.current_context available in the downstream app but not outside" do
    @downstream = ->(env) do
      refute_nil Aikido::Zen.current_context
      assert_kind_of Aikido::Zen::Context, Aikido::Zen.current_context
      @contexts << Aikido::Zen.current_context
      [200, {}, []]
    end

    result = @middleware.call(Rack::MockRequest.env_for("/"))

    assert_equal [200, {}, []], result
    assert_nil Aikido::Zen.current_context
  end

  test "exposes the context as env[aikido.context]" do
    env = Rack::MockRequest.env_for("/")

    @middleware.call(env)

    assert_kind_of Aikido::Zen::Context, env["aikido.context"]
  end

  test "separate threads get access to a different context object" do
    contexts = {}

    @downstream = ->(env) do
      contexts[Thread.current.object_id] = Aikido::Zen.current_context
    end

    t1 = Thread.new { @middleware.call(Rack::MockRequest.env_for("/foo")) }
    t2 = Thread.new { @middleware.call(Rack::MockRequest.env_for("/bar")) }

    t1.join
    t2.join

    assert_equal "/foo", contexts[t1.object_id].request.path
    assert_equal "/bar", contexts[t2.object_id].request.path
  end

  test "requests get tracked in our stats funnel" do
    assert_difference "Aikido::Zen.collector.stats.requests", +3 do
      @middleware.call(Rack::MockRequest.env_for("/"))
      @middleware.call(Rack::MockRequest.env_for("/"))
      @middleware.call(Rack::MockRequest.env_for("/"))
    end
  end
end
