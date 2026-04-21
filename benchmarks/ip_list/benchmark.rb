#!/usr/bin/env ruby

require "benchmark"
require "aikido-zen"

random_ipv4_ranges = (0..).lazy.map do
  ip_int = rand(2**32)
  prefix = rand(8..32)
  network = IPAddr.new(ip_int, Socket::AF_INET).mask(prefix)
  "#{network}/#{prefix}"
end

random_ipv6_ranges = (0..).lazy.map do
  ip_int = rand(2**128)
  prefix = rand(1..128)
  network = IPAddr.new(ip_int, Socket::AF_INET6).mask(prefix)
  "#{network}/#{prefix}"
end

random_ip_ranges = (0..).lazy.map do
  (rand < 0.5) ? random_ipv4_ranges.next : random_ipv6_ranges.next
end

if __FILE__ == $0
  ip_ranges = random_ip_ranges.take(1000)

  ip_list = Aikido::Zen::RuntimeSettings::IPList.from_json({
    "key" => "key",
    "source" => "source",
    "description" => "description",
    "ips" => ip_ranges
  })

  result = Benchmark.measure do
    ip_ranges.all? { |ip_range| ip_list.include?(ip_range) }
  end

  puts result
end
