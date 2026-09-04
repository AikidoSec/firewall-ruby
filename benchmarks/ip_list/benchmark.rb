#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark"
require "tmpdir"
require "fileutils"
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

  dir = Dir.mktmpdir("ip_list_benchmark")
  path = File.join(dir, "list.ipls")
  Aikido::Zen::Firewall::IPLists.write_from_json(path, [
    {"key" => "key", "source" => "source", "description" => "description", "ips" => ip_ranges}
  ])
  bundle = Aikido::Zen::Firewall::IPLists.new(path)

  result = Benchmark.measure do
    ip_ranges.all? { |ip_range| bundle.include?(ip_range) }
  end

  puts result

  bundle.close
  FileUtils.remove_entry(dir)
end
