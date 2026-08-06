#!/usr/bin/env ruby
# frozen_string_literal: true

# Compares two ways of looking up an IP list:
#
#   - Aikido::Zen::RuntimeSettings::IPList: in-process Integer ranges
#   - Aikido::Zen::IPLists::Data: same data, backed by a binary file read
#     via IO#pread/#pwrite instead of held as Ruby objects
#
# on:
#
#   1. raw #include? lookup throughput in a single process
#   2. memory footprint across several forked worker processes: Ruby's GC
#      touches every live object's header, which defeats fork's
#      copy-on-write sharing for plain Ruby objects, whereas the file-backed
#      version never holds the data as Ruby objects in the first place.
#
# Each of the three memory scenarios (baseline / runtime_settings / reader)
# runs in its own top-level `ruby` process (via BENCH_MODE), not just a
# forked child of one shared parent -- otherwise every scenario's forks
# would inherit the *other* scenarios' already-built data too, since it'd
# still be sitting in the one shared parent's heap.

require "benchmark"
require "tmpdir"
require "fileutils"
require "aikido-zen"

RANGE_COUNT = (ENV["RANGE_COUNT"] || 200_000).to_i
LOOKUP_COUNT = (ENV["LOOKUP_COUNT"] || 20_000).to_i
WORKER_COUNT = (ENV["WORKER_COUNT"] || 8).to_i

def random_cidr_strings(count)
  Array.new(count) do
    if rand < 0.5
      ip_int = rand(2**32)
      prefix = rand(8..32)
      "#{IPAddr.new(ip_int, Socket::AF_INET).mask(prefix)}/#{prefix}"
    else
      ip_int = rand(2**128)
      prefix = rand(1..128)
      "#{IPAddr.new(ip_int, Socket::AF_INET6).mask(prefix)}/#{prefix}"
    end
  end
end

def random_lookup_ips(count)
  Array.new(count) do
    (rand < 0.5) ? IPAddr.new(rand(2**32), Socket::AF_INET).to_s : IPAddr.new(rand(2**128), Socket::AF_INET6).to_s
  end
end

def build_runtime_settings_ip_list(cidrs)
  Aikido::Zen::RuntimeSettings::IPList.from_json({
    "key" => "key",
    "source" => "source",
    "description" => "description",
    "ips" => cidrs
  })
end

# Writes a plain file (not Tempfile, which unlinks itself once the Ruby
# object is GC'd -- this needs to keep existing on disk for independent
# processes/workers to open by path). ip_list already has #key/#description
# (from RuntimeSettings::IPList), so it can be handed straight to Data::Writer
# as the sole entry.
def write_data_file(dir, ip_list)
  path = File.join(dir, "list.ipls")
  Aikido::Zen::IPLists::Data::Writer.write(path, [ip_list])
  path
end

# A handful of full GC cycles plus a compaction pass, simulating a worker
# that's been alive for a while -- this is what actually dirties pages that
# were shared via fork's copy-on-write.
def settle_gc
  3.times { GC.start }
  GC.compact if GC.respond_to?(:compact)
end

def private_memory_kb(pid = Process.pid)
  rollup = File.read("/proc/#{pid}/smaps_rollup")
  clean = rollup[/^Private_Clean:\s+(\d+) kB/, 1].to_i
  dirty = rollup[/^Private_Dirty:\s+(\d+) kB/, 1].to_i
  clean + dirty
end

def shared_memory_kb(pid = Process.pid)
  rollup = File.read("/proc/#{pid}/smaps_rollup")
  clean = rollup[/^Shared_Clean:\s+(\d+) kB/, 1].to_i
  dirty = rollup[/^Shared_Dirty:\s+(\d+) kB/, 1].to_i
  clean + dirty
end

# Forks `worker_count` children. Each child runs the block, which must
# return [private_kb, shared_kb]; results are collected back via a pipe.
def fork_workers(worker_count)
  pipes = Array.new(worker_count) { IO.pipe }

  pipes.each do |read, write|
    fork do
      read.close
      private_kb, shared_kb = yield
      write.puts "#{private_kb} #{shared_kb}"
      write.close
      exit!(0)
    end
    write.close
  end

  results = pipes.map { |read, _write| read.read.split.map(&:to_i) }
  Process.waitall
  results
end

# Runs one of the memory scenarios and prints "private shared" lines, one
# per worker, to stdout -- this is what the driver process below shells out
# to, once per scenario, so each scenario starts from a clean process.
def run_memory_scenario(mode)
  results =
    case mode
    when "baseline"
      fork_workers(WORKER_COUNT) do
        settle_gc
        [private_memory_kb, shared_memory_kb]
      end
    when "runtime_settings"
      cidrs = Marshal.load(File.binread(ENV.fetch("BENCH_CIDRS_FILE")))
      lookup_ips = Marshal.load(File.binread(ENV.fetch("BENCH_LOOKUP_IPS_FILE")))
      ip_list = build_runtime_settings_ip_list(cidrs)

      fork_workers(WORKER_COUNT) do
        LOOKUP_COUNT.times { ip_list.include?(lookup_ips.sample) }
        settle_gc
        [private_memory_kb, shared_memory_kb]
      end
    when "reader"
      lookup_ips = Marshal.load(File.binread(ENV.fetch("BENCH_LOOKUP_IPS_FILE")))
      path = ENV.fetch("BENCH_DATA_PATH")

      fork_workers(WORKER_COUNT) do
        reader = Aikido::Zen::IPLists::Data::Reader.new(path)
        LOOKUP_COUNT.times { reader.include?(lookup_ips.sample) }
        settle_gc
        result = [private_memory_kb, shared_memory_kb]
        reader.close
        result
      end
    else
      raise ArgumentError, "unknown BENCH_MODE: #{mode.inspect}"
    end

  results.each { |private_kb, shared_kb| puts "#{private_kb} #{shared_kb}" }
end

# Shells out to this same script in child-process mode, so it starts from a
# clean process rather than inheriting whatever the driver already built.
def run_memory_scenario_in_subprocess(mode, extra_env = {})
  env = extra_env.merge(
    "BENCH_MODE" => mode,
    "RANGE_COUNT" => RANGE_COUNT.to_s,
    "LOOKUP_COUNT" => LOOKUP_COUNT.to_s,
    "WORKER_COUNT" => WORKER_COUNT.to_s
  )

  output = IO.popen(env, [RbConfig.ruby, "-Ilib", __FILE__], &:read)
  raise "subprocess for mode #{mode} failed" unless $?.success?

  output.lines.map { |line| line.split.map(&:to_i) }
end

if ENV["BENCH_MODE"]
  run_memory_scenario(ENV["BENCH_MODE"])
  exit 0
end

puts "RANGE_COUNT=#{RANGE_COUNT} LOOKUP_COUNT=#{LOOKUP_COUNT} WORKER_COUNT=#{WORKER_COUNT}"
puts

cidrs = random_cidr_strings(RANGE_COUNT)
ip_list = build_runtime_settings_ip_list(cidrs)
lookup_ips = random_lookup_ips(LOOKUP_COUNT)

dir = Dir.mktmpdir("reader_benchmark")
data_path = write_data_file(dir, ip_list)
cidrs_path = File.join(dir, "cidrs.marshal")
File.binwrite(cidrs_path, Marshal.dump(cidrs))
lookup_ips_path = File.join(dir, "lookup_ips.marshal")
File.binwrite(lookup_ips_path, Marshal.dump(lookup_ips))

puts "=== Part 1: lookup throughput (single process) ==="

runtime_settings_result = Benchmark.measure do
  lookup_ips.each { |ip| ip_list.include?(ip) }
end
puts "RuntimeSettings::IPList: #{runtime_settings_result}"

reader = Aikido::Zen::IPLists::Data::Reader.new(data_path)
reader_result = Benchmark.measure do
  lookup_ips.each { |ip| reader.include?(ip) }
end
puts "IPLists::Data::Reader (pread): #{reader_result}"
reader.close

puts
puts "=== Part 2: private memory across #{WORKER_COUNT} forked workers (each scenario in its own fresh process tree) ==="

baseline = run_memory_scenario_in_subprocess("baseline")
runtime_settings_workers = run_memory_scenario_in_subprocess("runtime_settings", "BENCH_CIDRS_FILE" => cidrs_path, "BENCH_LOOKUP_IPS_FILE" => lookup_ips_path)
reader_workers = run_memory_scenario_in_subprocess("reader", "BENCH_DATA_PATH" => data_path, "BENCH_LOOKUP_IPS_FILE" => lookup_ips_path)

[
  ["baseline (no IP list)", baseline],
  ["RuntimeSettings::IPList (built before fork)", runtime_settings_workers],
  ["IPLists::Data::Reader (pread, independently per worker)", reader_workers]
].each do |name, results|
  private_kbs = results.map(&:first)
  shared_kbs = results.map(&:last)

  puts "#{name}:"
  puts "  private kB per worker: #{private_kbs.inspect}"
  puts "  total private kB across #{WORKER_COUNT} workers: #{private_kbs.sum}"
  puts "  shared kB per worker:  #{shared_kbs.inspect}"
  puts
end

FileUtils.remove_entry(dir)
