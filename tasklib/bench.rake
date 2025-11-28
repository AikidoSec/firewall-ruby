# frozen_string_literal: true

require "socket"
require "timeout"
require_relative "wrk"

SERVER_PIDS = {}
PORT_PROTECTED = 3001
PORT_UNPROTECTED = 3002

def stop_servers
  SERVER_PIDS.each { |_, pid| Process.kill("TERM", pid) }
  SERVER_PIDS.clear
end

def boot_server(dir, port:, env: {})
  env["RAILS_MIN_THREADS"] = NUMBER_OF_THREADS
  env["RAILS_MAX_THREADS"] = NUMBER_OF_THREADS
  env["PORT"] = port.to_s
  env["SECRET_KEY_BASE"] = rand(36**64).to_s(36)

  Dir.chdir(dir) do
    SERVER_PIDS[port] = Process.spawn(
      env,
      "rails", "server", "--pid", "#{Dir.pwd}/tmp/pids/server.#{port}.pid", "-e", "production",
      out: "/dev/null"
    )
  rescue
    SERVER_PIDS.delete(port)
  end
end

def port_open?(port, timeout: 1)
  Timeout.timeout(timeout) do
    TCPSocket.new("127.0.0.1", port).close
    true
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
    false
  end
rescue Timeout::Error
  false
end

def wait_for_servers
  ports = SERVER_PIDS.keys

  Timeout.timeout(10) do
    ports.reject! { |port| port_open?(port) } while ports.any?
  end
rescue Timeout::Error
  raise "Could not reach ports: #{ports.join(", ")}"
end

Pathname.glob("sample_apps/*").select(&:directory?).each do |dir|
  namespace :bench do
    namespace dir.basename.to_s do
      desc "Run WRK benchmarks for the #{dir.basename} sample app"
      task wrk_run: [:boot_protected_app, :boot_unprotected_app] do
        throughput_decrease_limit_perc = 25
        if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0.0") && Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.1.0")
          # add higher limit for ruby 3.0
          throughput_decrease_limit_perc = 35
        end

        wait_for_servers
        run_benchmark(
          route_zen: "http://localhost:#{PORT_PROTECTED}/benchmark", # Application with Zen
          route_no_zen: "http://localhost:#{PORT_UNPROTECTED}/benchmark", # Application without Zen
          description: "An empty route (1ms simulated delay)",
          throughput_decrease_limit_perc: throughput_decrease_limit_perc,
          latency_increase_limit_ms: 200
        )
      ensure
        stop_servers
      end

      desc "Run K6 benchmarks for the #{dir.basename} sample app"
      task k6_run: [:boot_protected_app, :boot_unprotected_app] do
        wait_for_servers
        Dir.chdir("benchmarks") { sh "k6 run #{dir.basename}.js" }
      ensure
        stop_servers
      end

      task :boot_protected_app do
        boot_server(dir, port: PORT_PROTECTED)
      end

      task :boot_unprotected_app do
        boot_server(dir, port: PORT_UNPROTECTED, env: {"AIKIDO_DISABLE" => "true"})
      end
    end
  end
end
