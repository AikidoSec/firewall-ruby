# frozen_string_literal: true

require "socket"
require "timeout"

SERVER_PIDS = {}

def stop_servers
  SERVER_PIDS.each { |port, pid| Process.kill("TERM", pid) }
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

Pathname.glob("sample_apps/*").select(&:directory?).each do |dir|
  namespace :bench do
    namespace dir.basename.to_s do
      desc "Run benchmarks for the #{dir.basename} sample app"
      task run: [:boot_protected_app, :boot_unprotected_app] do
        sleep 3 # wait for the servers to boot
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
