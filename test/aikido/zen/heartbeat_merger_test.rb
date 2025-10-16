# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::HeartbeatMergerTest < ActiveSupport::TestCase
  setup do
    @config = Aikido::Zen.config
    @merger = Aikido::Zen::HeartbeatMerger.new(config: @config)
  end

  test "#merge returns nil for empty array" do
    assert_nil @merger.merge([])
  end

  test "#merge returns nil for nil input" do
    assert_nil @merger.merge(nil)
  end

  test "#merge combines two complete heartbeats" do
    # Heartbeat from worker process 1
    heartbeat1 = {
      "type" => "heartbeat",
      "time" => 1757692839981,
      "agent" => {
        "dryMode" => false,
        "hostname" => "web-server-1",
        "version" => "1.0.0",
        "library" => "firewall-ruby"
      },
      "routes" => [
        {
          "method" => "GET",
          "path" => "/api/users/:id",
          "hits" => 150,
          "apispec" => {
            "query" => {
              "type" => "object",
              "properties" => {"include" => {"type" => "string"}}
            }
          }
        },
        {
          "method" => "POST",
          "path" => "/api/posts",
          "hits" => 25,
          "apispec" => {
            "body" => {
              "type" => "json",
              "schema" => {
                "type" => "object",
                "properties" => {
                  "title" => {"type" => "string"},
                  "content" => {"type" => "string"}
                }
              }
            }
          }
        }
      ],
      "stats" => {
        "startedAt" => 1757692802871,
        "endedAt" => 1757692839981,
        "requests" => {
          "total" => 200,
          "aborted" => 3,
          "attacksDetected" => {
            "total" => 5,
            "blocked" => 3
          }
        },
        "sinks" => {
          "Mysql2::Client#query" => {
            "total" => 450,
            "interceptorThrewError" => 1,
            "attacksDetected" => {
              "total" => 3,
              "blocked" => 2
            }
          },
          "File.read" => {
            "total" => 89,
            "interceptorThrewError" => 0,
            "attacksDetected" => {
              "total" => 2,
              "blocked" => 1
            }
          }
        }
      },
      "users" => [
        {
          "id" => "user-123",
          "name" => "Alice Smith",
          "lastIpAddress" => "192.168.1.100",
          "firstSeenAt" => 1757692809790,
          "lastSeenAt" => 1757692830000
        },
        {
          "id" => "user-456",
          "name" => "Bob Jones",
          "lastIpAddress" => "192.168.1.101",
          "firstSeenAt" => 1757692815000,
          "lastSeenAt" => 1757692825000
        }
      ],
      "hostnames" => [
        {"hostname" => "api.stripe.com", "port" => 443},
        {"hostname" => "database.internal", "port" => 5432}
      ],
      "middlewareInstalled" => true
    }

    # Heartbeat from worker process 2
    heartbeat2 = {
      "type" => "heartbeat",
      "time" => 1757692840500,
      "agent" => {
        "dryMode" => false,
        "hostname" => "web-server-2",
        "version" => "1.0.0",
        "library" => "firewall-ruby"
      },
      "routes" => [
        {
          "method" => "GET",
          "path" => "/api/users/:id",
          "hits" => 95,
          "apispec" => {
            "query" => {
              "type" => "object",
              "properties" => {"fields" => {"type" => "string"}}
            }
          }
        },
        {
          "method" => "DELETE",
          "path" => "/api/posts/:id",
          "hits" => 12,
          "apispec" => {}
        }
      ],
      "stats" => {
        "startedAt" => 1757692800000,
        "endedAt" => 1757692841000,
        "requests" => {
          "total" => 150,
          "aborted" => 1,
          "attacksDetected" => {
            "total" => 2,
            "blocked" => 1
          }
        },
        "sinks" => {
          "Mysql2::Client#query" => {
            "total" => 320,
            "interceptorThrewError" => 0,
            "attacksDetected" => {
              "total" => 1,
              "blocked" => 0
            }
          },
          "Net::HTTP#request" => {
            "total" => 45,
            "interceptorThrewError" => 2,
            "attacksDetected" => {
              "total" => 1,
              "blocked" => 1
            }
          }
        }
      },
      "users" => [
        {
          "id" => "user-123",
          "name" => "Alice Johnson",
          "lastIpAddress" => "192.168.1.105",
          "firstSeenAt" => 1757692805000,
          "lastSeenAt" => 1757692838000
        },
        {
          "id" => "user-789",
          "name" => "Charlie Brown",
          "lastIpAddress" => "10.0.0.50",
          "firstSeenAt" => 1757692820000,
          "lastSeenAt" => 1757692835000
        }
      ],
      "hostnames" => [
        {"hostname" => "api.stripe.com", "port" => 443},
        {"hostname" => "redis.internal", "port" => 6379}
      ],
      "middlewareInstalled" => false
    }

    at = Time.now.utc
    result = @merger.merge([heartbeat1, heartbeat2], at: at)

    expected = {
      "type" => "heartbeat",
      "time" => at.to_i * 1000,
      "agent" => {
        "dryMode" => false,
        "hostname" => "web-server-1",
        "version" => "1.0.0",
        "library" => "firewall-ruby"
      },
      "routes" => [
        {
          "method" => "GET",
          "path" => "/api/users/:id",
          "hits" => 245,
          "apispec" => {
            "query" => {
              "type" => "object",
              "properties" => {
                "include" => {"type" => "string"}
              }
            }
          }
        },
        {
          "method" => "POST",
          "path" => "/api/posts",
          "hits" => 25,
          "apispec" => {
            "body" => {
              "type" => "json",
              "schema" => {
                "type" => "object",
                "properties" => {
                  "title" => {"type" => "string"},
                  "content" => {"type" => "string"}
                }
              }
            }
          }
        },
        {
          "method" => "DELETE",
          "path" => "/api/posts/:id",
          "hits" => 12,
          "apispec" => {}
        }
      ],
      "stats" => {
        "startedAt" => 1757692800000,
        "endedAt" => 1757692841000,
        "requests" => {
          "total" => 350,
          "aborted" => 4,
          "attacksDetected" => {
            "total" => 7,
            "blocked" => 4
          }
        },
        "sinks" => {
          "Mysql2::Client#query" => {
            "total" => 770,
            "interceptorThrewError" => 1,
            "attacksDetected" => {
              "total" => 4,
              "blocked" => 2
            }
          },
          "File.read" => {
            "total" => 89,
            "interceptorThrewError" => 0,
            "attacksDetected" => {
              "total" => 2,
              "blocked" => 1
            }
          },
          "Net::HTTP#request" => {
            "total" => 45,
            "interceptorThrewError" => 2,
            "attacksDetected" => {
              "total" => 1,
              "blocked" => 1
            }
          }
        }
      },
      "users" => [
        {
          "id" => "user-123",
          "name" => "Alice Johnson",
          "lastIpAddress" => "192.168.1.105",
          "firstSeenAt" => 1757692805000,
          "lastSeenAt" => 1757692838000
        },
        {
          "id" => "user-456",
          "name" => "Bob Jones",
          "lastIpAddress" => "192.168.1.101",
          "firstSeenAt" => 1757692815000,
          "lastSeenAt" => 1757692825000
        },
        {
          "id" => "user-789",
          "name" => "Charlie Brown",
          "lastIpAddress" => "10.0.0.50",
          "firstSeenAt" => 1757692820000,
          "lastSeenAt" => 1757692835000
        }
      ],
      "hostnames" => [
        {"hostname" => "api.stripe.com", "port" => 443},
        {"hostname" => "database.internal", "port" => 5432},
        {"hostname" => "redis.internal", "port" => 6379}
      ],
      "middlewareInstalled" => true
    }

    assert_equal expected, result
  end
end
