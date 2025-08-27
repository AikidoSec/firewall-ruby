# frozen_string_literal: true

module Aikido::Zen::Middleware
  def self.request_from(env)
    if (current_context = Aikido::Zen.current_context)
      current_context.request
    else
      Aikido::Zen::Context.from_rack_env(env).request
    end
  end
end
