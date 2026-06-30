# frozen_string_literal: true

require "test_helper"

module IPCHelpers
  def build_ipc_server(secret = Aikido::Zen.secret)
    Aikido::Zen::IPC::Server.new(secret)
  end

  def build_ipc_client(server, secret = Aikido::Zen.secret)
    Aikido::Zen::IPC::Client.new(
      secret,
      server.host,
      server.port,
      connect_timeout: 1,
      handshake_timeout: 1
    )
  end

  def start_ipc_server(secret = Aikido::Zen.secret, &block)
    server = build_ipc_server(secret)
    server.start(&block)
    server
  end

  def start_ipc_client(server, secret = Aikido::Zen.secret, &block)
    client = build_ipc_client(server, secret)
    client.start(&block)
    client
  end
end

module RPCHelpers
  def build_rpc_server(secret = Aikido::Zen.secret, logger: Aikido::Zen.config.logger)
    Aikido::Zen::RPC::Server.new(secret, logger: logger)
  end

  def build_rpc_client(server, secret = Aikido::Zen.secret, logger: Aikido::Zen.config.logger)
    Aikido::Zen::RPC::Client.new(secret, server.host, server.port, logger: logger)
  end

  def start_rpc_server(secret = Aikido::Zen.secret, logger: Aikido::Zen.config.logger, &block)
    server = build_rpc_server(secret, logger: logger)
    block&.call(server)
    server.start
    server
  end

  def start_rpc_client(server, secret = Aikido::Zen.secret, logger: Aikido::Zen.config.logger)
    client = build_rpc_client(server, secret, logger: logger)
    client.start
    client
  end
end

class Aikido::Zen::RPC::ServerTest < ActiveSupport::TestCase
  include IPCHelpers
  include RPCHelpers
  include Aikido::Zen::IPC::FramedIO

  test "skips messages with an invalid structure and continues processing" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, JSON.generate(["bad", "hello"]), nil, 1)
    write_frame_with_timeout(socket, JSON.generate(["abc", "echo", ["hello"], {}]), nil, 1)
    response = JSON.parse(read_frame_with_timeout(socket, nil, 2))

    assert_equal ["abc", "hello", nil], response
  ensure
    client.close
    server.stop
  end

  test "#respond only sends the first response when called multiple times" do
    server = start_rpc_server do |server|
      server.handle("repeat") do |respond|
        respond.call("first")
        respond.call("second")
      end
    end

    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, JSON.generate(["abc", "repeat", [], {}]), nil, 1)
    response = JSON.parse(read_frame_with_timeout(socket, nil, 2))

    assert_equal ["abc", "first", nil], response
  ensure
    client.close
    server.stop
  end

  test "logs unexpected errors and drops the connection" do
    server = start_rpc_server
    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, "invalid JSON", nil, 1)
    assert_raises(EOFError) { read_frame_with_timeout(socket, nil, 1) }

    assert_logged :error, /invalid JSON/
  ensure
    client.close
    server.stop
  end
end

class Aikido::Zen::RPC::ClientTest < ActiveSupport::TestCase
  include IPCHelpers
  include RPCHelpers
  include Aikido::Zen::IPC::FramedIO

  test "#invoke skips messages with an invalid structure and continues processing" do
    server = start_ipc_server do |socket|
      raw = read_frame_with_timeout(socket, nil, 1)
      id, _name, _args, _kwargs = JSON.parse(raw)
      write_frame_with_timeout(socket, JSON.generate(["bad"]), nil, 1)
      write_frame_with_timeout(socket, JSON.generate([id, "hello", nil]), nil, 1)
    end

    client = start_rpc_client(server)

    result = client.invoke("echo", timeout: 2)
    assert_equal "hello", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke ignores responses with an unknown ID" do
    server = start_ipc_server do |socket|
      raw = read_frame_with_timeout(socket, nil, 1)
      id, _name, _args, _kwargs = JSON.parse(raw)
      write_frame_with_timeout(socket, JSON.generate(["unknown-id", "ignored", nil]), nil, 1)
      write_frame_with_timeout(socket, JSON.generate([id, "hello", nil]), nil, 1)
    end

    client = start_rpc_client(server)

    result = client.invoke("echo", timeout: 2)
    assert_equal "hello", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke raises on server disconnect" do
    server = start_ipc_server do |socket|
      read_frame_with_timeout(socket, nil, 2)
      socket.close
    end

    client = start_rpc_client(server)

    assert_raises(EOFError, Errno::ECONNRESET) do
      client.invoke("echo", timeout: 2)
    end
  ensure
    client.stop
    server.stop
  end

  test "#invoke raises RuntimeError when the server responds with an error" do
    server = start_ipc_server do |socket|
      raw = read_frame_with_timeout(socket, nil, 2)
      id, _name, _args, _kwargs = JSON.parse(raw)
      write_frame_with_timeout(socket, JSON.generate([id, nil, "something went wrong"]), nil, 1)
    end

    client = start_rpc_client(server)

    err = assert_raises(RuntimeError) do
      client.invoke("echo", timeout: 2)
    end

    assert_equal "something went wrong", err.message
  ensure
    client.stop
    server.stop
  end

  test "logs unexpected errors" do
    gate = Concurrent::CountDownLatch.new(1)

    server = start_ipc_server do |socket|
      write_frame_with_timeout(socket, "invalid JSON", nil, 1)
    end

    logger = Aikido::Zen.config.logger
    logger.stub(:error, ->(msg) {
      logger.add(Logger::ERROR, msg)
      gate.count_down
    }) do
      client = start_rpc_client(server)
      gate.wait(2)
      client.stop
    end

    assert_logged :error, /JSON/
  ensure
    server.stop
  end
end

class Aikido::Zen::RPC::ConnectionTest < ActiveSupport::TestCase
  include RPCHelpers

  test "#invoke calls the handler and returns the result" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, text| respond.call(text) }
    end

    client = start_rpc_client(server)

    result = client.invoke("echo", "hello", timeout: 2)

    assert_equal "hello", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke raises Errno::ETIMEDOUT on timeout" do
    gate = Concurrent::CountDownLatch.new(1)

    server = start_rpc_server do |server|
      server.handle("slow") { gate.wait }
    end

    client = start_rpc_client(server)

    assert_raises(Errno::ETIMEDOUT) do
      client.invoke("slow", timeout: 0.1)
    end
  ensure
    gate.count_down

    client.stop
    server.stop
  end

  test "#invoke raises RuntimeError when the handler is not registered" do
    server = start_rpc_server

    client = start_rpc_client(server)

    err = assert_raises(RuntimeError) do
      client.invoke("nonexistent", timeout: 2)
    end

    assert_match(/nonexistent/, err.message)
  ensure
    client.stop
    server.stop
  end

  test "#invoke passes positional arguments to the handler" do
    server = start_rpc_server do |server|
      server.handle("add") { |respond, a, b| respond.call(a + b) }
    end

    client = start_rpc_client(server)

    result = client.invoke("add", 3, 4, timeout: 2)

    assert_equal 7, result
  ensure
    client.stop
    server.stop
  end

  test "#invoke passes keyword arguments to the handler" do
    server = start_rpc_server do |server|
      server.handle("greet") { |respond, name:, greeting: "Hello"| respond.call("#{greeting}, #{name}!") }
    end

    client = start_rpc_client(server)

    result = client.invoke("greet", name: "Alice", timeout: 2)

    assert_equal "Hello, Alice!", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke passes positional and keyword arguments to the handler" do
    server = start_rpc_server do |server|
      server.handle("greet") { |respond, greeting, name:| respond.call("#{greeting}, #{name}!") }
    end

    client = start_rpc_client(server)

    result = client.invoke("greet", "Hello", name: "Alice", timeout: 2)

    assert_equal "Hello, Alice!", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke returns nil when the handler explicitly responds with nil" do
    server = start_rpc_server do |server|
      server.handle("null") { |respond| respond.call(nil) }
    end

    client = start_rpc_client(server)

    result = client.invoke("null", timeout: 2)

    assert_nil result
  ensure
    client.stop
    server.stop
  end

  test "#invoke returns nil when the handler does not respond explicitly" do
    server = start_rpc_server do |server|
      server.handle("noop") {}
    end

    client = start_rpc_client(server)

    result = client.invoke("noop", timeout: 2)

    assert_nil result
  ensure
    client.stop
    server.stop
  end

  test "#invoke returns immediately when the handler responds" do
    gate = Concurrent::CountDownLatch.new(1)

    server = start_rpc_server do |server|
      server.handle("work") do |respond|
        respond.call(nil)
        gate.wait
      end
    end

    client = start_rpc_client(server)

    result = client.invoke("work", timeout: 2)

    assert_nil result
  ensure
    gate.count_down

    client.stop
    server.stop
  end

  test "#invoke returns a string when the handler responds with a symbol" do
    server = start_rpc_server do |server|
      server.handle("symbolize") { |respond| respond.call(:ok) }
    end

    client = start_rpc_client(server)

    result = client.invoke("symbolize", timeout: 2)

    assert_equal "ok", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke handles complex nested structures" do
    data = {"users" => [{"id" => 1, "name" => "Alice"}, {"id" => 2, "name" => "Bob"}]}

    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = start_rpc_client(server)

    result = client.invoke("echo", data, timeout: 2)

    assert_equal data, result
  ensure
    client.stop
    server.stop
  end

  test "#invoke returns the result when the handler raises after responding" do
    server = start_rpc_server do |server|
      server.handle("risky") do |respond|
        respond.call("safe result")
        raise "something went wrong"
      end
    end

    client = start_rpc_client(server)

    result = client.invoke("risky", timeout: 2)

    assert_equal "safe result", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke propagates errors raised inside the handler" do
    server = start_rpc_server do |server|
      server.handle("boom") { raise "something went wrong" }
    end

    client = start_rpc_client(server)

    err = assert_raises(RuntimeError) do
      client.invoke("boom", timeout: 2)
    end

    assert_equal "something went wrong", err.message
  ensure
    client.stop
    server.stop
  end

  test "#invoke routes concurrent responses to the correct callers with single handler" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = start_rpc_client(server)

    threads = 5.times.map do |i|
      Thread.new do
        [i, client.invoke("echo", i, timeout: 2)]
      end
    end

    threads.each do |thread|
      input, output = thread.value
      assert_equal input, output
    end
  ensure
    client.stop
    server.stop
  end

  test "#invoke routes concurrent responses to the correct callers with multiple handlers" do
    server = start_rpc_server do |server|
      server.handle("double") { |respond, n| respond.call(n * 2) }
      server.handle("negate") { |respond, n| respond.call(-n) }
    end

    client = start_rpc_client(server)

    doubles = 3.times.map do |i|
      Thread.new do
        [i, client.invoke("double", i, timeout: 2)]
      end
    end

    negates = 3.times.map do |i|
      Thread.new do
        [i, client.invoke("negate", i, timeout: 2)]
      end
    end

    doubles.each do |thread|
      i, result = thread.value
      assert_equal i * 2, result
    end

    negates.each do |thread|
      i, result = thread.value
      assert_equal(-i, result)
    end
  ensure
    client.stop
    server.stop
  end
end
