# frozen_string_literal: true

module Aikido::Zen
  # Merges multiple heartbeat JSON objects from child processes into a single combined heartbeat.
  # This reduces the number of API calls and data transferred when using forked workers.
  class HeartbeatMerger
    def initialize(config: Aikido::Zen.config)
      @config = config
    end

    # Merge an array of heartbeat JSON objects into a single combined heartbeat
    #
    # @param heartbeats [Array<Hash>] array of heartbeat JSON objects
    # @return [Hash, nil] merged heartbeat or nil if array is empty
    def merge(heartbeats)
      return nil if heartbeats.nil? || heartbeats.empty?

      # Start with the first heartbeat as the base
      merged = heartbeats.first.dup

      # Merge the rest
      heartbeats[1..].each do |heartbeat|
        merge_into!(merged, heartbeat)
      end

      merged
    end

    private def merge_into!(target, source)
      # Merge routes
      target_routes = target["routes"] || target[:routes] || []
      source_routes = source["routes"] || source[:routes] || []
      target["routes"] = merge_routes(target_routes, source_routes)

      # Merge stats
      target_stats = target["stats"] || target[:stats] || {}
      source_stats = source["stats"] || source[:stats] || {}
      target["stats"] = merge_stats(target_stats, source_stats)

      # Merge users
      target_users = target["users"] || target[:users] || []
      source_users = source["users"] || source[:users] || []
      target["users"] = merge_users(target_users, source_users)

      # Merge hostnames
      target_hosts = target["hostnames"] || target[:hostnames] || []
      source_hosts = source["hostnames"] || source[:hostnames] || []
      target["hostnames"] = merge_hostnames(target_hosts, source_hosts)

      # Merge middleware flag (true if any process has it)
      target["middlewareInstalled"] ||= source["middlewareInstalled"] || source[:middlewareInstalled]

      target
    end

    private def merge_routes(target_routes, source_routes)
      routes_map = {}

      # Add all target routes to map
      target_routes.each do |route|
        key = "#{route['method'] || route[:method]}:#{route['path'] || route[:path]}"
        routes_map[key] = route.dup
      end

      # Merge source routes
      source_routes.each do |route|
        method = route['method'] || route[:method]
        path = route['path'] || route[:path]
        key = "#{method}:#{path}"

        if routes_map[key]
          # Merge hits
          routes_map[key]['hits'] = (routes_map[key]['hits'] || 0) + (route['hits'] || route[:hits] || 0)

          # Merge schema - just keep the first one for simplicity
          # Full schema merging from JSON is complex because Definition expects
          # nested properties to be Definition objects, not hashes
          target_spec = routes_map[key]['apispec'] || routes_map[key][:apispec]
          source_spec = route['apispec'] || route[:apispec]

          # Only update if target doesn't have a schema
          if target_spec.nil? || target_spec.empty?
            routes_map[key]['apispec'] = source_spec || {}
          end
        else
          routes_map[key] = route.dup
        end
      end

      routes_map.values
    end

    private def merge_stats(target_stats, source_stats)
      # Merge request counts
      target_requests = target_stats['requests'] || target_stats[:requests] || {}
      source_requests = source_stats['requests'] || source_stats[:requests] || {}

      merged_requests = {
        'total' => (target_requests['total'] || target_requests[:total] || 0) + (source_requests['total'] || source_requests[:total] || 0),
        'aborted' => (target_requests['aborted'] || target_requests[:aborted] || 0) + (source_requests['aborted'] || source_requests[:aborted] || 0),
        'attacksDetected' => {
          'total' => ((target_requests.dig('attacksDetected', 'total') || target_requests.dig(:attacksDetected, :total) || 0) +
                      (source_requests.dig('attacksDetected', 'total') || source_requests.dig(:attacksDetected, :total) || 0)),
          'blocked' => ((target_requests.dig('attacksDetected', 'blocked') || target_requests.dig(:attacksDetected, :blocked) || 0) +
                        (source_requests.dig('attacksDetected', 'blocked') || source_requests.dig(:attacksDetected, :blocked) || 0))
        }
      }

      # Merge timestamps - keep earliest start and latest end
      target_start = target_stats['startedAt'] || target_stats[:startedAt]
      source_start = source_stats['startedAt'] || source_stats[:startedAt]
      merged_start = [target_start, source_start].compact.min

      target_end = target_stats['endedAt'] || target_stats[:endedAt]
      source_end = source_stats['endedAt'] || source_stats[:endedAt]
      merged_end = [target_end, source_end].compact.max

      # Merge sinks
      target_sinks = target_stats['sinks'] || target_stats[:sinks] || {}
      source_sinks = source_stats['sinks'] || source_stats[:sinks] || {}
      merged_sinks = merge_sinks(target_sinks, source_sinks)

      {
        'startedAt' => merged_start,
        'endedAt' => merged_end,
        'requests' => merged_requests,
        'sinks' => merged_sinks
      }.compact
    end

    private def merge_sinks(target_sinks, source_sinks)
      merged = {}

      # Add all target sinks
      target_sinks.each do |sink_name, sink_data|
        merged[sink_name] = sink_data.dup
      end

      # Merge source sinks
      source_sinks.each do |sink_name, sink_data|
        if merged[sink_name]
          # Merge counts
          merged[sink_name]['total'] = (merged[sink_name]['total'] || 0) + (sink_data['total'] || sink_data[:total] || 0)
          merged[sink_name]['interceptorThrewError'] = (merged[sink_name]['interceptorThrewError'] || 0) + (sink_data['interceptorThrewError'] || sink_data[:interceptorThrewError] || 0)

          target_attacks = merged[sink_name]['attacksDetected'] || {}
          source_attacks = sink_data['attacksDetected'] || sink_data[:attacksDetected] || {}

          merged[sink_name]['attacksDetected'] = {
            'total' => (target_attacks['total'] || target_attacks[:total] || 0) + (source_attacks['total'] || source_attacks[:total] || 0),
            'blocked' => (target_attacks['blocked'] || target_attacks[:blocked] || 0) + (source_attacks['blocked'] || source_attacks[:blocked] || 0)
          }
        else
          merged[sink_name] = sink_data.dup
        end
      end

      merged
    end

    private def merge_users(target_users, source_users)
      users_map = {}

      # Add all target users to map
      target_users.each do |user|
        user_id = user['id'] || user[:id]
        users_map[user_id] = user.dup if user_id
      end

      # Merge source users
      source_users.each do |user|
        user_id = user['id'] || user[:id]
        next unless user_id

        if users_map[user_id]
          # Keep the latest lastSeenAt and lastIpAddress
          target_last_seen = users_map[user_id]['lastSeenAt'] || users_map[user_id][:lastSeenAt] || 0
          source_last_seen = user['lastSeenAt'] || user[:lastSeenAt] || 0

          if source_last_seen > target_last_seen
            users_map[user_id]['lastSeenAt'] = source_last_seen
            users_map[user_id]['lastIpAddress'] = user['lastIpAddress'] || user[:lastIpAddress]
          end

          # Keep the earliest firstSeenAt
          target_first_seen = users_map[user_id]['firstSeenAt'] || users_map[user_id][:firstSeenAt]
          source_first_seen = user['firstSeenAt'] || user[:firstSeenAt]
          users_map[user_id]['firstSeenAt'] = [target_first_seen, source_first_seen].compact.min
        else
          users_map[user_id] = user.dup
        end
      end

      users_map.values
    end

    private def merge_hostnames(target_hosts, source_hosts)
      hosts_map = {}

      # Add all target hosts to map
      target_hosts.each do |host|
        hostname = host['hostname'] || host[:hostname]
        port = host['port'] || host[:port]
        key = "#{hostname}:#{port}"
        hosts_map[key] = host.dup if hostname
      end

      # Add source hosts (unique by hostname:port)
      source_hosts.each do |host|
        hostname = host['hostname'] || host[:hostname]
        port = host['port'] || host[:port]
        next unless hostname

        key = "#{hostname}:#{port}"
        hosts_map[key] ||= host.dup
      end

      hosts_map.values
    end

    # Recursively convert string keys to symbol keys
    private def symbolize_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(key, value), result|
          new_key = key.is_a?(String) ? key.to_sym : key
          result[new_key] = symbolize_keys(value)
        end
      when Array
        obj.map { |item| symbolize_keys(item) }
      else
        obj
      end
    end
  end
end
