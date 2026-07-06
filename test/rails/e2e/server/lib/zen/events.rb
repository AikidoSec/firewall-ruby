# frozen_string_literal: true

module Zen
  module Events
    MUTEX = Mutex.new

    @events = Hash.new { |h, k| h[k] = [] }

    class << self
      def capture(event, app)
        MUTEX.synchronize { @events[app.id] << event }
      end

      def list(app)
        MUTEX.synchronize { @events[app.id].dup }
      end
    end
  end
end
