# frozen_string_literal: true

module Zen
  module Config
    MUTEX = Mutex.new

    @configs = {}
    @subscribers = Hash.new { |h, k| h[k] = [] }
    @blocked_ips = {}
    @allowed_ips = {}
    @monitored_ips = {}
    @blocked_user_agents = {}
    @monitored_user_agents = {}
    @user_agent_details = {}

    class << self
      def get(app)
        MUTEX.synchronize { @configs[app.id] ||= default_config(app) }
      end

      def update(app, attrs = {})
        MUTEX.synchronize do
          @configs[app.id] ||= default_config(app)
          @configs[app.id].merge!(attrs)
          @configs[app.id]["configUpdatedAt"] = now_ms
        end

        notify(app.id)

        true
      end

      def subscribe(app_id, &block)
        MUTEX.synchronize { @subscribers[app_id] << block }

        block
      end

      def unsubscribe(app_id, block)
        MUTEX.synchronize { @subscribers[app_id].delete(block) }
      end

      def blocked_ips(app)
        MUTEX.synchronize { @blocked_ips[app.id] || [] }
      end

      def allowed_ips(app)
        MUTEX.synchronize { @allowed_ips[app.id] || [] }
      end

      def monitored_ips(app)
        MUTEX.synchronize { @monitored_ips[app.id] || [] }
      end

      def blocked_user_agents(app)
        MUTEX.synchronize { @blocked_user_agents[app.id] || "" }
      end

      def monitored_user_agents(app)
        MUTEX.synchronize { @monitored_user_agents[app.id] || "" }
      end

      def user_agent_details(app)
        MUTEX.synchronize { @user_agent_details[app.id] || [] }
      end

      def update_blocked_ips(app, ips)
        MUTEX.synchronize { @blocked_ips[app.id] = ips }

        update(app)
      end

      def update_allowed_ips(app, ips)
        MUTEX.synchronize { @allowed_ips[app.id] = ips }

        update(app)
      end

      def update_monitored_ips(app, ips)
        MUTEX.synchronize { @monitored_ips[app.id] = ips }

        update(app)
      end

      def update_blocked_user_agents(app, user_agents)
        MUTEX.synchronize { @blocked_user_agents[app.id] = user_agents }

        update(app)
      end

      def update_monitored_user_agents(app, user_agents)
        MUTEX.synchronize { @monitored_user_agents[app.id] = user_agents }

        update(app)
      end

      def update_user_agent_details(app, user_agents)
        MUTEX.synchronize { @user_agent_details[app.id] = user_agents }

        update(app)
      end

      private

      def default_config(app)
        {
          "success" => true,
          "serviceId" => app.id,
          "configUpdatedAt" => app.config_updated_at,
          "heartbeatIntervalInMS" => 10 * 60 * 1000,
          "endpoints" => [],
          "blockedUserIds" => [],
          "allowedIPAddresses" => [],
          "blockNewOutgoingRequests" => false,
          "domains" => [],
          "excludedUserIdsFromRateLimiting" => []
        }
      end

      def notify(app_id)
        MUTEX.synchronize { @subscribers[app_id].dup }.each(&:call)
      end

      def now_ms
        Time.now.to_i * 1000
      end
    end
  end
end
