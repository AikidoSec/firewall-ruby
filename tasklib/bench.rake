# frozen_string_literal: true

require "socket"
require "timeout"

SERVER_PIDS = {}

def stop_servers
  SERVER_PIDS.each { |_, pid| Process.kill("TERM", pid) }
  SERVER_PIDS.clear
end

def boot_server(dir, port:, env: {})
  env["PORT"] = port.to_s

  Dir.chdir(dir) do
    SERVER_PIDS[port] = Process.spawn(
      env,
      "rails", "server", "--pid", "#{Dir.pwd}/tmp/pids/server.#{port}.pid",
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
        Dir.chdir("benchmarks") { sh "k6 run #{dir.basename}.js" }
      ensure
        stop_servers
      end

      task :boot_protected_app do
        boot_server(dir, port: 3001)
      end

      task :boot_unprotected_app do
        boot_server(dir, port: 3002, env: {"AIKIDO_DISABLE" => "true"})
      end
    end

    task default: "#{dir.basename}:run"
  end
end
