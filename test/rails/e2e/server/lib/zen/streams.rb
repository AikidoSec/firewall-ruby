# frozen_string_literal: true

module Zen
  module Streams
    PING_INTERVAL = 30

    MUTEX = Mutex.new

    @connections = Hash.new { |h, k| h[k] = [] }
    @pinger = nil

    class << self
      # @param app_id [String]
      # @param conn [Sinatra::Helpers::Stream]
      # @param queue [Queue] pushed :ping, so conn's own thread does the write
      def register(app_id, conn, queue)
        MUTEX.synchronize { @connections[app_id] << [conn, queue] }
      end

      def remove(app_id, conn)
        MUTEX.synchronize { @connections[app_id].reject! { |c, _| c == conn } }
      end

      def close_all(app_id)
        conns = MUTEX.synchronize { @connections.delete(app_id) || [] }
        conns.each do |conn, _|
          conn.close
        rescue
          nil
        end
      end

      # Starts the single background thread that pings every open connection.
      # Safe to call more than once; only the first call has any effect.
      #
      # @return [void]
      def start_pinger(interval: PING_INTERVAL)
        return if @pinger

        MUTEX.synchronize do
          @pinger ||= Thread.new do
            loop do
              sleep interval
              ping_all
            end
          end
        end

        nil
      end

      private

      def ping_all
        all_connections.each do |_, queue|
          queue << :ping
        rescue ClosedQueueError
          # disconnected
        end
      end

      def all_connections
        MUTEX.synchronize { @connections.values.flatten(1) }
      end
    end
  end
end
