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
          @fork_mutex = Mutex.new
        end

        def call(env)
          pid = Process.pid

          if pid != @pid.value
            @fork_mutex.synchronize do
              if pid != @pid.value
                Aikido::Zen.fork!

                @pid.value = pid
              end
            end
          end

          @app.call(env)
        end
      end
    end
  end
end
