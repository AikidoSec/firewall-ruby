#!/usr/bin/env ruby

require "benchmark"
require "securerandom"
require "logger"
require "aikido-zen"

def run(duration, concurrency)
  secret = SecureRandom.bytes(32)
  logger = Logger.new(File::NULL)

  server = Aikido::Zen::RPC::Server.start(secret, logger: logger) do |server|
    server.handle("echo") { |respond, value| respond.call(value) }
  end

  client = Aikido::Zen::RPC::Client.start(secret, server.host, server.port, logger: logger)

  calls = Concurrent::AtomicFixnum.new(0)

  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration

  result = Benchmark.measure do
    threads = concurrency.times.map do
      Thread.new do
        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          client.invoke("echo", "hello", timeout: 5.0)

          calls.increment
        end
      end
    end

    threads.each(&:join)
  end

  [calls.value, result.real]
ensure
  client.stop
  server.stop
end

def report(label, total_calls, real)
  rate = total_calls / real
  latency_ms = real / total_calls * 1000

  puts label
  puts "#{rate.round} calls/sec, #{latency_ms.round(3)} ms/call"
end

if __FILE__ == $0
  duration = (ENV["DURATION"] || 5).to_i
  concurrency = (ENV["CONCURRENCY"] || 1).to_i

  calls, real = run(duration, concurrency)

  report("RPC echo (concurrency: #{concurrency})", calls, real)
end
