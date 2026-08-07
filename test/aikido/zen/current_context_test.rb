# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::CurrentContextTest < ActiveSupport::TestCase
  def build_context
    Aikido::Zen::Context.from_rack_env(Rack::MockRequest.env_for("/"))
  end

  teardown do
    Aikido::Zen.current_context = nil
  end

  test "the context is readable in the fiber that set it" do
    context = Aikido::Zen.current_context = build_context

    assert_same context, Aikido::Zen.current_context
  end

  test "the context is copied into child fibers" do
    context = Aikido::Zen.current_context = build_context

    assert_same context, Fiber.new { Aikido::Zen.current_context }.resume
  end

  # ActionController::Live runs the action in its own thread, where the
  # fiber-local is gone. See https://github.com/AikidoSec/firewall-ruby/issues/357
  test "the context survives a thread hop that shares the execution state" do
    context = Aikido::Zen.current_context = build_context

    main = Thread.current
    in_thread = Thread.new {
      ActiveSupport::IsolatedExecutionState.share_with(main)
      Aikido::Zen.current_context
    }.value

    assert_same context, in_thread
  end

  test "a thread that does not share the execution state has no context" do
    Aikido::Zen.current_context = build_context

    assert_nil Thread.new { Aikido::Zen.current_context }.value
  end

  test "clearing the context clears it for a sharing thread too" do
    Aikido::Zen.current_context = build_context
    Aikido::Zen.current_context = nil

    main = Thread.current
    in_thread = Thread.new {
      ActiveSupport::IsolatedExecutionState.share_with(main)
      Aikido::Zen.current_context
    }.value

    assert_nil in_thread
  end
end
