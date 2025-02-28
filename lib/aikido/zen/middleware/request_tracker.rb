# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    # Rack middleware used to track request
    # It implements the logic under that which is considered worthy of being tracked.
    class RequestTracker
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      end
    end
  end
end
