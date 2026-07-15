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

          @pid = Concurrent::AtomicFixnum.new(Process.pid)
        end

        def call(env)
          new_pid = Process.pid
          old_pid = @pid.value

          if new_pid != old_pid && @pid.compare_and_set(old_pid, new_pid)
            Aikido::Zen.fork!
          end

          @app.call(env)
        end
      end
    end
  end
end
