require "open3"
require "time"

def generate_wrk_command_for_url(url)
  # Define the command with wrk included
  "wrk --threads 5 --connections 200 --duration 20s #{url}"
end

def cold_start(url)
  10.times do
    _, err, status = Open3.capture3("curl #{url}")

    if status != 0
      puts err
      exit(-1)
    end
  end
end

def extract_requests_and_latency_tuple(out, err, status)
  if status == 0
    # Extracting requests/sec
    requests_sec_match = out.match(/Requests\/sec:\s+([\d.]+)/)
    requests_sec = requests_sec_match[1].to_f if requests_sec_match

    # Extracting latency
    latency_match = out.match(/Latency\s+([\d.]+)(ms|s)/)
    latency = latency_match[1].to_f if latency_match
    latency_unit = latency_match[2] if latency_match

    if latency_unit == "s"
      latency *= 1000
    end

    {requests_sec: requests_sec, latency: latency}
  else
    puts "Error occurred running benchmark command:"
    puts err.strip
    exit(1)
  end
end

def run_benchmark(route_no_zen:, route_zen:, description:, throughput_decrease_limit_perc:, latency_increase_limit_ms:)
  # Cold start
  cold_start(route_no_zen)
  cold_start(route_zen)

  out, err, status = Open3.capture3(generate_wrk_command_for_url(route_zen))
  puts <<~MSG
    WRK OUTPUT
    ================
      FIREWALL ENABLED:
        #{out}
    ----------------
  MSG
  result_zen_enabled = extract_requests_and_latency_tuple(out, err, status)

  out, err, status = Open3.capture3(generate_wrk_command_for_url(route_no_zen))
  puts <<~MSG
      FIREWALL DISABLED:
        #{out}
    ================
  MSG
  result_zen_disabled = extract_requests_and_latency_tuple(out, err, status)

  # Check if the command was successful
  if result_zen_enabled && result_zen_disabled
    # Print the output, which should be the Requests/sec value
    puts "[ZEN ENABLED ] Requests/sec: #{result_zen_enabled[:requests_sec]} | Latency in ms: #{result_zen_enabled[:latency]}"
    puts "[ZEN DISABLED] Requests/sec: #{result_zen_disabled[:requests_sec]} | Latency in ms: #{result_zen_disabled[:latency]}"

    latency_increase_ms = (result_zen_enabled[:latency] - result_zen_disabled[:latency]).round(2)
    puts "-> Delta in ms: #{latency_increase_ms}ms after running load test on #{description}"

    throughput_decrease_perc = ((result_zen_disabled[:requests_sec] - result_zen_enabled[:requests_sec]) / result_zen_disabled[:requests_sec] * 100).round
    puts "-> #{throughput_decrease_perc}% decrease in throughput after running load test on #{description}\n"

    if latency_increase_ms >= latency_increase_limit_ms
      exit(1)
    end
    if throughput_decrease_perc >= throughput_decrease_limit_perc
      exit(1)
    end
  end
end
