# frozen_string_literal: true

require "securerandom"
require "rack/utils"

module Zen
  module Apps
    MUTEX = Mutex.new

    @apps = []
    @next_id = 1

    App = Struct.new(:id, :token, :config_updated_at)

    class << self
      def create
        MUTEX.synchronize do
          id = @next_id
          @next_id += 1

          token = "AIK_RUNTIME_1_#{id}_#{SecureRandom.alphanumeric(48)}"

          app = App.new(id, token, now_ms)

          @apps << app

          app
        end
      end

      def remove(app)
        MUTEX.synchronize do
          @apps.reject! { |a| a.id == app.id }
        end
      end

      def find(token)
        MUTEX.synchronize do
          @apps.find { |a| Rack::Utils.secure_compare(a.token, token) }
        end
      end

      private

      def now_ms
        Time.now.to_i * 1000
      end
    end
  end
end
