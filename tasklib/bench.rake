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
      desc "Run benchmarks for the #{dir.basename} sample app"
      task run: [:boot_protected_app, :boot_unprotected_app] do
        wait_for_servers
        run_benchmark(
          route_zen: "http://localhost:#{PORT_PROTECTED}/benchmark", # Application with Zen
          route_no_zen: "http://localhost:#{PORT_UNPROTECTED}/benchmark", # Application without Zen
          description: "An empty route (1ms simulated delay)",
          percentage_limit: 15,
          ms_limit: 200
        )
      ensure
        stop_servers
      end

      task :boot_protected_app do
        boot_server(dir, port: PORT_PROTECTED)
      end

      task :boot_unprotected_app do
        boot_server(dir, port: PORT_UNPROTECTED, env: {"AIKIDO_DISABLED" => "true"})
      end

      task :run_local do
        run_benchmark(
          route_zen: "http://localhost:3001/benchmark", # Application with Zen
          route_no_zen: "http://localhost:3002/benchmark", # Application without Zen
          description: "An empty route (1ms simulated delay)",
          percentage_limit: 15,
          ms_limit: 200
        )
      end
    end

    task default: "#{dir.basename}:run"
  end
end
