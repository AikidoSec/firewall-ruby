# frozen_string_literal: true

module Aikido
  module Zen
    module Middleware
      # This middleware is responsible for detecting when a process has forked
      # (e.g., in a Puma or Unicorn worker) and resetting the state of the
      # Aikido Zen agent. It should be inserted early in the middleware stack.
      class ForkDetector
        def initialize(app)
          @app = app
        end

        def call(env)
          # This is the single, reliable trigger point for the fork check.
          Aikido::Zen.check_and_handle_fork

          @app.call(env)
        end
      end
    end
  end
end
