require "open3"
require "time"

def generate_wrk_command_for_url(url)
  # Define the command with wrk included
  "wrk --threads 12 --connections 400 --duration 15s #{url}"
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

    [requests_sec, latency]
  else
    puts "Error occurred running benchmark command:"
    puts err.strip
    exit(1)
  end
end

def run_benchmark(route_no_zen:, route_zen:, description:, percentage_limit:, ms_limit:)
  # Cold start
  cold_start(route_no_zen)
  cold_start(route_zen)

  out, err, status = Open3.capture3(generate_wrk_command_for_url(route_zen))
  result_nofw = extract_requests_and_latency_tuple(out, err, status)

  out, err, status = Open3.capture3(generate_wrk_command_for_url(route_no_zen))
  result_fw = extract_requests_and_latency_tuple(out, err, status)

  # Check if the command was successful
  if result_nofw && result_fw
    # Print the output, which should be the Requests/sec value
    puts "[FIREWALL-ON] Requests/sec: #{result_fw[0]} | Latency in ms: #{result_fw[1]}"
    puts "[FIREWALL-OFF] Requests/sec: #{result_nofw[0]} | Latency in ms: #{result_nofw[1]}"

    delta_in_ms = (result_fw[1] - result_nofw[1]).round(2)
    puts "-> Delta in ms: #{delta_in_ms}ms after running load test on #{description}"

    delay_percentage = ((result_nofw[0] - result_fw[0]) / result_nofw[0] * 100).round
    puts "-> #{delay_percentage}% decrease in throughput after running load test on #{description} \n"

    if delta_in_ms > ms_limit
      exit(1)
    end
    if delay_percentage > percentage_limit
      exit(1)
    end
  end
end
