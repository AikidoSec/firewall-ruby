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

    result = @middleware.call({"PATH_INFO" => "/"})

    assert_equal [200, {}, []], result
    assert_nil Aikido::Zen.current_context
  end

  test "separate threads get access to a different context object" do
    contexts = {}

    @downstream = ->(env) do
      contexts[Thread.current.object_id] = Aikido::Zen.current_context
    end

    t1 = Thread.new { @middleware.call({"PATH_INFO" => "/foo"}) }
    t2 = Thread.new { @middleware.call({"PATH_INFO" => "/bar"}) }

    t1.join
    t2.join

    assert_equal "/foo", contexts[t1.object_id].request.path
    assert_equal "/bar", contexts[t2.object_id].request.path
  end

  test "requests get tracked in our stats funnel" do
    agent = Aikido::Zen.send(:agent)

    assert_difference -> { agent.stats.requests }, +3 do
      @middleware.call({"PATH_INFO" => "/"})
      @middleware.call({"PATH_INFO" => "/"})
      @middleware.call({"PATH_INFO" => "/"})
    end
  end
end
