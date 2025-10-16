# frozen_string_literal: true

module Aikido::Zen
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

      # Start with an empty merged heartbeat using the first heartbeat's metadata
      first = heartbeats.first
      merged = {
        "type" => first["type"],
        "time" => first["time"],
        "agent" => first["agent"],
        "routes" => [],
        "stats" => {
          "startedAt" => nil,
          "endedAt" => nil,
          "requests" => {
            "total" => 0,
            "aborted" => 0,
            "attacksDetected" => {"total" => 0, "blocked" => 0}
          },
          "sinks" => {}
        },
        "users" => [],
        "hostnames" => [],
        "middlewareInstalled" => false
      }

      # Accumulate data from all heartbeats
      heartbeats.each do |heartbeat|
        merge_routes_into!(merged, heartbeat["routes"] || [])
        merge_stats_into!(merged, heartbeat["stats"] || {})
        merge_users_into!(merged, heartbeat["users"] || [])
        merge_hostnames_into!(merged, heartbeat["hostnames"] || [])
        merged["middlewareInstalled"] ||= heartbeat["middlewareInstalled"]
      end

      merged
    end

    private def merge_routes_into!(merged, routes)
      routes_by_key = merged["routes"].each_with_object({}) do |route, hash|
        key = "#{route['method']}:#{route['path']}"
        hash[key] = route
      end

      routes.each do |route|
        key = "#{route['method']}:#{route['path']}"

        if routes_by_key[key]
          routes_by_key[key]['hits'] += route['hits'] || 0

          # Keep first schema (TODO: schema merging from JSON is complex)
          if routes_by_key[key]['apispec'].nil? || routes_by_key[key]['apispec'].empty?
            routes_by_key[key]['apispec'] = route['apispec'] || {}
          end
        else
          new_route = route.dup
          routes_by_key[key] = new_route
          merged["routes"] << new_route
        end
      end
    end

    private def merge_stats_into!(merged, stats)
      merged_stats = merged["stats"]

      requests = stats['requests'] || {}
      merged_stats["requests"]["total"] += requests['total'] || 0
      merged_stats["requests"]["aborted"] += requests['aborted'] || 0
      merged_stats["requests"]["attacksDetected"]["total"] += requests.dig('attacksDetected', 'total') || 0
      merged_stats["requests"]["attacksDetected"]["blocked"] += requests.dig('attacksDetected', 'blocked') || 0

      if stats['startedAt']
        merged_stats["startedAt"] = [merged_stats["startedAt"], stats['startedAt']].compact.min
      end

      if stats['endedAt']
        merged_stats["endedAt"] = [merged_stats["endedAt"], stats['endedAt']].compact.max
      end

      (stats['sinks'] || {}).each do |sink_name, sink_data|
        merge_sink_into!(merged_stats["sinks"], sink_name, sink_data)
      end
    end

    private def merge_sink_into!(sinks, sink_name, sink_data)
      if sinks[sink_name]
        # Add to existing sink
        sinks[sink_name]['total'] += sink_data['total'] || 0
        sinks[sink_name]['interceptorThrewError'] += sink_data['interceptorThrewError'] || 0
        sinks[sink_name]['attacksDetected']['total'] += sink_data.dig('attacksDetected', 'total') || 0
        sinks[sink_name]['attacksDetected']['blocked'] += sink_data.dig('attacksDetected', 'blocked') || 0
      else
        # Add new sink
        sinks[sink_name] = {
          'total' => sink_data['total'] || 0,
          'interceptorThrewError' => sink_data['interceptorThrewError'] || 0,
          'attacksDetected' => {
            'total' => sink_data.dig('attacksDetected', 'total') || 0,
            'blocked' => sink_data.dig('attacksDetected', 'blocked') || 0
          }
        }
      end
    end

    private def merge_users_into!(merged, users)
      users_by_id = merged["users"].each_with_object({}) do |user, hash|
        hash[user['id']] = user
      end

      users.each do |user|
        user_id = user['id']
        next unless user_id

        if users_by_id[user_id]
          existing = users_by_id[user_id]

          if (user['lastSeenAt'] || 0) > (existing['lastSeenAt'] || 0)
            existing['lastSeenAt'] = user['lastSeenAt']
            existing['lastIpAddress'] = user['lastIpAddress']
            existing['name'] = user['name'] if user['name']
          end

          existing['firstSeenAt'] = [existing['firstSeenAt'], user['firstSeenAt']].compact.min
        else
          new_user = user.dup
          users_by_id[user_id] = new_user
          merged["users"] << new_user
        end
      end
    end

    private def merge_hostnames_into!(merged, hostnames)
      hostnames_by_key = merged["hostnames"].each_with_object({}) do |host, hash|
        key = "#{host['hostname']}:#{host['port']}"
        hash[key] = host
      end

      hostnames.each do |host|
        hostname = host['hostname']
        next unless hostname

        key = "#{hostname}:#{host['port']}"
        unless hostnames_by_key[key]
          new_host = host.dup
          hostnames_by_key[key] = new_host
          merged["hostnames"] << new_host
        end
      end
    end
  end
end
