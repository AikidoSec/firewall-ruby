# frozen_string_literal: true

namespace :ci do
  desc "Set up the test database"
  task setup: ["db:migrate", "db:test:prepare"]

  desc "Start the mock server and Rails server then run the Rails end to end tests"
  task :e2e do
    require "net/http"
    require "json"
    require "socket"

    mock_port = Integer(ENV.fetch("MOCK_PORT", 4567))
    rails_port = Integer(ENV.fetch("PORT", 3000))

    mock_uri = "http://127.0.0.1:#{mock_port}"
    rails_uri = "http://127.0.0.1:#{rails_port}"

    server_dir = File.expand_path("../../../server", __dir__)

    log_dir = File.expand_path("../../log", __dir__)
    FileUtils.mkdir_p(log_dir)

    mock_log = File.join(log_dir, "mock_server.log")
    rails_log = File.join(log_dir, "rails_server.log")

    pids = []

    begin
      puts "Starting mock server on port #{mock_port}..."

      pids << spawn(
        {"PORT" => mock_port.to_s, "BUNDLE_GEMFILE" => nil},
        "bundle exec ruby app.rb",
        chdir: server_dir,
        out: mock_log,
        err: mock_log
      )

      wait_for_tcp(mock_uri, label: "mock server", log_file: mock_log)

      puts "Registering with mock server..."

      response = Net::HTTP.post(
        URI("#{mock_uri}/api/runtime/apps"),
        "{}",
        "Content-Type" => "application/json"
      )

      mock_token = JSON.parse(response.body).fetch("token")

      puts "Obtained mock token: #{mock_token[0, 20]}..."

      puts "Configuring mock server..."

      config_uri = URI("#{mock_uri}/api/runtime/config")
      config_req = Net::HTTP::Post.new(config_uri)
      config_req["Authorization"] = mock_token
      config_req["Content-Type"] = "application/json"
      config_req.body = {"heartbeatIntervalInMS" => 1_000}.to_json
      Net::HTTP.start(config_uri.host, config_uri.port) { |http| http.request(config_req) }

      puts "Starting Rails server on port #{rails_port}..."

      pids << spawn(
        {
          "RAILS_ENV" => "test",
          "PORT" => rails_port.to_s,
          "AIKIDO_TOKEN" => mock_token,
          "AIKIDO_ENDPOINT" => mock_uri,
          "AIKIDO_REALTIME_ENDPOINT" => mock_uri,
          "AIKIDO_REALTIME_SETTINGS_UPDATES_ENDPOINT" => mock_uri
        },
        "bundle exec rails server",
        out: rails_log,
        err: rails_log
      )

      wait_for_http("#{rails_uri}/up", label: "Rails server", log_file: rails_log)

      puts "Running Rails end to end tests..."

      success = system(
        {
          "MOCK_SERVER_URI" => mock_uri,
          "MOCK_TOKEN" => mock_token,
          "RAILS_SERVER_URI" => rails_uri
        },
        "bundle exec rails test test/e2e/"
      )

      exit(1) unless success
    ensure
      pids.each { |pid| stop_process(pid) }
    end
  end

  private

  # Terminates +pid+, escalating to SIGKILL if it does not exit within
  # +timeout+ seconds.
  # @param pid [Integer]
  # @param timeout [Numeric] seconds to wait after SIGTERM before SIGKILL
  # @return [void]
  def stop_process(pid, timeout: 10)
    Process.kill("TERM", pid)

    deadline = Time.now + timeout

    until Process.wait(pid, Process::WNOHANG)
      if Time.now > deadline
        Process.kill("KILL", pid)
        Process.wait(pid)
        break
      end

      sleep 0.1
    end
  rescue Errno::ESRCH, Errno::ECHILD
    # already gone
  end

  # Prints the contents of +log_file+ to aid debugging a startup timeout.
  # @param log_file [String, nil]
  # @return [void]
  def dump_log(log_file)
    return unless log_file && File.exist?(log_file)

    puts "\n--- #{log_file} ---"
    puts File.read(log_file)
    puts "--- end #{log_file} ---\n\n"
  end

  # Calls +block+ every 0.5s until it returns true or +max_wait+ seconds elapse.
  # @param label [String] name used in progress and error messages
  # @param max_wait [Integer] maximum seconds to wait before raising
  # @param log_file [String, nil] path to a log file to print if we time out
  # @return [void]
  # @raise [RuntimeError] if +block+ does not return true within +max_wait+ seconds
  def wait_until(label:, max_wait: 30, log_file: nil)
    deadline = Time.now + max_wait

    loop do
      if yield
        puts "  #{label} is up."
        return
      end

      if Time.now > deadline
        dump_log(log_file)
        raise "#{label} did not start within #{max_wait}s"
      end

      sleep 0.5
    end
  end

  # Blocks until a TCP connection to +uri+ succeeds or +max_wait+ seconds elapse.
  # @param uri [String] the URI to connect to
  # @param label [String] name used in progress and error messages
  # @param max_wait [Integer] maximum seconds to wait before raising
  # @param log_file [String, nil] path to a log file to print if we time out
  # @return [void]
  def wait_for_tcp(uri, label:, max_wait: 30, log_file: nil)
    uri = URI(uri)

    wait_until(label: label, max_wait: max_wait, log_file: log_file) do
      TCPSocket.open(uri.host, uri.port) {}
      true
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
      false
    end
  end

  # Blocks until a GET request to +uri+ succeeds or +max_wait+ seconds elapse.
  # @param uri [String] the URI to request
  # @param label [String] name used in progress and error messages
  # @param max_wait [Integer] maximum seconds to wait before raising
  # @param log_file [String, nil] path to a log file to print if we time out
  # @return [void]
  def wait_for_http(uri, label:, max_wait: 30, log_file: nil)
    uri = URI(uri)

    wait_until(label: label, max_wait: max_wait, log_file: log_file) do
      Net::HTTP.get_response(uri).code.start_with?("2")
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, EOFError
      false
    end
  end
end
