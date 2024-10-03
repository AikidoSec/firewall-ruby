# frozen_string_literal: true

# Helpers to test attacks in sink tests.
module SinkAttackHelpers
  def set_context_from_request_to(request_uri, env = {})
    self.class.teardown { Aikido::Zen.current_context = nil }

    env = Rack::MockRequest.env_for(request_uri, env)
    Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(env)
  end

  def assert_attack(matcher, &block)
    Aikido::Zen.config.blocking_mode = true

    exception = assert_raises Aikido::Zen::UnderAttackError do
      yield
    end

    assert matcher === exception.attack,
      "Expected #{exception.attack.inspect} to match #{matcher.inspect}"

    exception
  end

  def refute_attack(&block)
    Aikido::Zen.config.blocking_mode = true

    assert_nothing_raised do
      yield
    end
  end
end
