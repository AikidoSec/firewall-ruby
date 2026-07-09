#!/usr/bin/env ruby

require "benchmark"
require "securerandom"
require "aikido-zen"

class BasicIO
  def initialize(data, timeout: 5)
    @data = data
    @size = data.bytesize
    @timeout = timeout
  end

  def read(socket)
    buffer = String.new(encoding: Encoding::BINARY)

    while buffer.bytesize < @size
      case chunk = socket.read_nonblock(@size - buffer.bytesize, exception: false)
      when :wait_readable
        raise Errno::ETIMEDOUT, "read timed out" unless IO.select([socket], nil, nil, @timeout)
      when nil
        raise EOFError
      else
        buffer << chunk
      end
    end

    buffer
  end

  def write(socket)
    written = 0

    while written < @data.bytesize
      case n = socket.write_nonblock(@data.byteslice(written..), exception: false)
      when :wait_writable
        raise Errno::ETIMEDOUT, "write timed out" unless IO.select(nil, [socket], nil, @timeout)
      else
        written += n
      end
    end
  end
end

class TimedIO
  include Aikido::Zen::IPC::TimedIO

  def initialize(data, timeout: 5)
    @data = data
    @size = data.bytesize
    @timeout = timeout
  end

  def read(socket)
    read_with_deadline(socket, @size, Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout)
  end

  def write(socket)
    write_with_deadline(socket, @data, Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout)
  end
end

class FramedIO
  include Aikido::Zen::IPC::FramedIO

  def initialize(data, timeout: 5)
    @data = data
    @timeout = timeout
  end

  def read(socket)
    read_frame_with_timeout(socket, nil, @timeout)
  end

  def write(socket)
    write_frame_with_timeout(socket, @data, nil, @timeout)
  end
end

def run(duration, io)
  secret = SecureRandom.bytes(32)

  server = Aikido::Zen::IPC::Server.start(secret) do |socket|
    loop do
      io.read(socket)
    end
  rescue EOFError, Errno::ECONNRESET, Errno::EPIPE
    # disconnected
  rescue IOError
    # client stopped
  end

  client = Aikido::Zen::IPC::Client.new(secret, server.host, server.port)

  sent = 0

  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration

  result = Benchmark.measure do
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      io.write(client.socket)

      sent += 1
    end
  end

  [sent, result.real]
ensure
  client.close
  server.stop
end

def report(label, sent, real, data_size, baseline: nil)
  rate = sent / real
  mib_per_sec = rate * data_size / (1024 * 1024)

  puts label
  puts "#{rate.round} messages/sec, #{mib_per_sec.round(2)} MiB/sec"

  if baseline
    overhead = 100 - (100.0 * rate / baseline)
    puts "#{overhead.round(1)}% fewer messages/sec than baseline"
  end
end

if __FILE__ == $0
  duration = (ENV["DURATION"] || 5).to_i
  data_size = (ENV["DATA_SIZE"] || 1024).to_i

  data = SecureRandom.bytes(data_size)

  basic_io = BasicIO.new(data)
  basic_io_sent, basic_io_real = run(duration, basic_io)
  report("baseline", basic_io_sent, basic_io_real, data_size)
  basic_io_rate = basic_io_sent / basic_io_real

  puts

  timed_io = TimedIO.new(data)
  timed_io_sent, timed_io_real = run(duration, timed_io)
  report("TimedIO", timed_io_sent, timed_io_real, data_size, baseline: basic_io_rate)

  puts

  framed_io = FramedIO.new(data)
  framed_io_sent, framed_io_real = run(duration, framed_io)
  report("FramedIO", framed_io_sent, framed_io_real, data_size, baseline: basic_io_rate)
end
