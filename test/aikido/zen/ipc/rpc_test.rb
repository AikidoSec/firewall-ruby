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
      connect_timeout: 1.0,
      handshake_timeout: 1.0
    )
  end

  def start_ipc_server(secret = Aikido::Zen.secret, &block)
    Aikido::Zen::IPC::Server.start(secret, &block)
  end

  def start_ipc_client(server, secret = Aikido::Zen.secret, &block)
    Aikido::Zen::IPC::Client.start(
      secret,
      server.host,
      server.port,
      connect_timeout: 1.0,
      handshake_timeout: 1.0,
      &block
    )
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
    Aikido::Zen::RPC::Server.start(secret, logger: logger, &block)
  end

  def start_rpc_client(server, secret = Aikido::Zen.secret, logger: Aikido::Zen.config.logger)
    Aikido::Zen::RPC::Client.start(secret, server.host, server.port, logger: logger)
  end
end

class Aikido::Zen::RPC::ServerTest < ActiveSupport::TestCase
  include IPCHelpers
  include RPCHelpers
  include Aikido::Zen::IPC::FramedIO

  test "#initialize binds to 127.0.0.1 on a free port" do
    server = build_rpc_server

    assert_equal "127.0.0.1", server.host
    assert_operator server.port, :>, 0
  ensure
    server.close
  end

  test "#close causes subsequent connection attempts to fail" do
    server = start_rpc_server

    server.close

    assert_raises(Errno::ECONNREFUSED) do
      build_ipc_client(server)
    end
  end

  test "#close does not stop the server" do
    server = start_rpc_server

    server.close

    assert_equal true, server.stop
  end

  test "#close does not disconnect existing clients" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = start_rpc_client(server)

    server.close

    result = client.invoke("echo", 2.0, "hello")
    assert_equal "hello", result
  ensure
    client.stop
    server.stop
  end

  test "skips non-array messages and continues processing" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, JSON.generate("not an array"), nil, 1.0)
    write_frame_with_timeout(socket, JSON.generate(["ok", "echo", ["ok-value"], {}]), nil, 1.0)

    response = JSON.parse(read_frame_with_timeout(socket, nil, 2.0))
    assert_equal ["ok", "ok-value", nil], response

    assert_raises(Errno::ETIMEDOUT) { read_frame_with_timeout(socket, nil, 0.1) }
  ensure
    client.close
    server.stop
  end

  test "skips messages with the wrong length and continues processing" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, JSON.generate(["poison", "echo", ["poison-value"]]), nil, 1.0)
    write_frame_with_timeout(socket, JSON.generate(["ok", "echo", ["ok-value"], {}]), nil, 1.0)

    response = JSON.parse(read_frame_with_timeout(socket, nil, 2.0))
    assert_equal ["ok", "ok-value", nil], response

    assert_raises(Errno::ETIMEDOUT) { read_frame_with_timeout(socket, nil, 0.1) }
  ensure
    client.close
    server.stop
  end

  test "skips messages with a non-string id and continues processing" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, JSON.generate([123, "echo", ["poison-value"], {}]), nil, 1.0)
    write_frame_with_timeout(socket, JSON.generate(["ok", "echo", ["ok-value"], {}]), nil, 1.0)

    response = JSON.parse(read_frame_with_timeout(socket, nil, 2.0))
    assert_equal ["ok", "ok-value", nil], response

    assert_raises(Errno::ETIMEDOUT) { read_frame_with_timeout(socket, nil, 0.1) }
  ensure
    client.close
    server.stop
  end

  test "skips messages with a non-string name and continues processing" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, JSON.generate(["poison", 123, ["poison-value"], {}]), nil, 1.0)
    write_frame_with_timeout(socket, JSON.generate(["ok", "echo", ["ok-value"], {}]), nil, 1.0)

    response = JSON.parse(read_frame_with_timeout(socket, nil, 2.0))
    assert_equal ["ok", "ok-value", nil], response

    assert_raises(Errno::ETIMEDOUT) { read_frame_with_timeout(socket, nil, 0.1) }
  ensure
    client.close
    server.stop
  end

  test "skips messages with non-array positional arguments and continues processing" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, JSON.generate(["poison", "echo", "poison-value", {}]), nil, 1.0)
    write_frame_with_timeout(socket, JSON.generate(["ok", "echo", ["ok-value"], {}]), nil, 1.0)

    response = JSON.parse(read_frame_with_timeout(socket, nil, 2.0))
    assert_equal ["ok", "ok-value", nil], response

    assert_raises(Errno::ETIMEDOUT) { read_frame_with_timeout(socket, nil, 0.1) }
  ensure
    client.close
    server.stop
  end

  test "skips messages with non-hash keyword arguments and continues processing" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, JSON.generate(["poison", "echo", ["poison-value"], []]), nil, 1.0)
    write_frame_with_timeout(socket, JSON.generate(["ok", "echo", ["ok-value"], {}]), nil, 1.0)

    response = JSON.parse(read_frame_with_timeout(socket, nil, 2.0))
    assert_equal ["ok", "ok-value", nil], response

    assert_raises(Errno::ETIMEDOUT) { read_frame_with_timeout(socket, nil, 0.1) }
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

    write_frame_with_timeout(socket, JSON.generate(["abc", "repeat", [], {}]), nil, 1.0)
    response = JSON.parse(read_frame_with_timeout(socket, nil, 2.0))

    assert_equal ["abc", "first", nil], response
  ensure
    client.close
    server.stop
  end

  test "logs unexpected errors and drops the connection" do
    server = start_rpc_server
    client = build_ipc_client(server)
    socket = client.socket

    write_frame_with_timeout(socket, "invalid JSON", nil, 1.0)
    assert_raises(EOFError) { read_frame_with_timeout(socket, nil, 1.0) }

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

  test "#close causes subsequent #invoke calls to raise" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = start_rpc_client(server)
    client.close

    assert_raises(IOError) do
      client.invoke("echo", 1.0, "hello")
    end
  ensure
    server.stop
  end

  test "#stop causes subsequent #invoke calls to raise" do
    server = start_rpc_server do |server|
      server.handle("echo") { |respond, value| respond.call(value) }
    end

    client = start_rpc_client(server)
    client.stop

    assert_raises(IOError) do
      client.invoke("echo", 1.0, "hello")
    end
  ensure
    server.stop
  end

  test "#stop does not raise when the connection is already closed" do
    server = start_rpc_server
    client = start_rpc_client(server)

    client.close

    assert_nothing_raised { client.stop }
  ensure
    server.stop
  end

  test "#invoke skips non-array messages and continues processing" do
    server = start_ipc_server do |socket|
      raw = read_frame_with_timeout(socket, nil, 1.0)
      id, _name, _args, _kwargs = JSON.parse(raw)
      write_frame_with_timeout(socket, JSON.generate("not an array"), nil, 1.0)
      write_frame_with_timeout(socket, JSON.generate([id, "ok-value", nil]), nil, 1.0)
    end

    client = start_rpc_client(server)

    result = client.invoke("echo", 2.0)
    assert_equal "ok-value", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke skips messages with the wrong length and continues processing" do
    server = start_ipc_server do |socket|
      raw = read_frame_with_timeout(socket, nil, 1.0)
      id, _name, _args, _kwargs = JSON.parse(raw)
      write_frame_with_timeout(socket, JSON.generate(["poison-value"]), nil, 1.0)
      write_frame_with_timeout(socket, JSON.generate([id, "ok-value", nil]), nil, 1.0)
    end

    client = start_rpc_client(server)

    result = client.invoke("echo", 2.0)
    assert_equal "ok-value", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke skips messages with a non-string id and continues processing" do
    server = start_ipc_server do |socket|
      raw = read_frame_with_timeout(socket, nil, 1.0)
      id, _name, _args, _kwargs = JSON.parse(raw)
      write_frame_with_timeout(socket, JSON.generate([123, "poison-value", nil]), nil, 1.0)
      write_frame_with_timeout(socket, JSON.generate([id, "ok-value", nil]), nil, 1.0)
    end

    client = start_rpc_client(server)

    result = client.invoke("echo", 2.0)
    assert_equal "ok-value", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke ignores responses with an unknown ID" do
    server = start_ipc_server do |socket|
      raw = read_frame_with_timeout(socket, nil, 1.0)
      id, _name, _args, _kwargs = JSON.parse(raw)
      write_frame_with_timeout(socket, JSON.generate(["unknown-id", "ignored", nil]), nil, 1.0)
      write_frame_with_timeout(socket, JSON.generate([id, "hello", nil]), nil, 1.0)
    end

    client = start_rpc_client(server)

    result = client.invoke("echo", 2.0)
    assert_equal "hello", result
  ensure
    client.stop
    server.stop
  end

  test "#invoke raises on server disconnect" do
    server = start_ipc_server do |socket|
      read_frame_with_timeout(socket, nil, 2.0)
      socket.close
    end

    client = start_rpc_client(server)

    assert_raises(EOFError, Errno::ECONNRESET) do
      client.invoke("echo", 2.0)
    end
  ensure
    client.stop
    server.stop
  end

  test "#invoke raises RuntimeError when the server responds with an error" do
    server = start_ipc_server do |socket|
      raw = read_frame_with_timeout(socket, nil, 2.0)
      id, _name, _args, _kwargs = JSON.parse(raw)
      write_frame_with_timeout(socket, JSON.generate([id, nil, "something went wrong"]), nil, 1.0)
    end

    client = start_rpc_client(server)

    err = assert_raises(RuntimeError) do
      client.invoke("echo", 2.0)
    end

    assert_equal "something went wrong", err.message
  ensure
    client.stop
    server.stop
  end

  test "logs unexpected errors" do
    gate = Concurrent::CountDownLatch.new(1)

    server = start_ipc_server do |socket|
      write_frame_with_timeout(socket, "invalid JSON", nil, 1.0)
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

  test "#reconnect is not triggered by default" do
    gate = Concurrent::CountDownLatch.new(1)

    server = start_ipc_server { gate.wait }

    connects = Concurrent::AtomicFixnum.new(0)

    client = Aikido::Zen::RPC::Client.start(
      Aikido::Zen.secret,
      server.host,
      server.port
    ) { connects.increment }

    wait_until(timeout: 1.0) { connects.value == 1 }

    client.stop

    sleep 1.0

    assert_equal 1, connects.value
  ensure
    gate.count_down
    server.stop
  end

  test "#reconnect is triggered when enabled" do
    gate = Concurrent::CountDownLatch.new(1)
    attempts = Concurrent::AtomicFixnum.new(0)

    server = start_ipc_server do |socket|
      if attempts.increment == 1
        socket.close
      else
        gate.wait
      end
    end

    connects = Concurrent::AtomicFixnum.new(0)

    client = Aikido::Zen::RPC::Client.start(
      Aikido::Zen.secret,
      server.host,
      server.port,
      reconnect: true
    ) { connects.increment }

    wait_until(timeout: 1.0) { connects.value == 2 }

    sleep 1.0

    assert_equal 2, connects.value
  ensure
    gate.count_down
    client.stop
    server.stop
  end

  test "#reconnect is not triggered after #stop when enabled" do
    gate = Concurrent::CountDownLatch.new(1)

    server = start_ipc_server { gate.wait }

    connects = Concurrent::AtomicFixnum.new(0)

    client = Aikido::Zen::RPC::Client.start(
      Aikido::Zen.secret,
      server.host,
      server.port,
      reconnect: true
    ) { connects.increment }

    wait_until(timeout: 1.0) { connects.value == 1 }

    client.stop

    sleep 1.0

    assert_equal 1, connects.value
  ensure
    gate.count_down
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

    result = client.invoke("echo", 2.0, "hello")

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
      client.invoke("slow", 0.1)
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
      client.invoke("nonexistent", 2.0)
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

    result = client.invoke("add", 2.0, 3, 4)

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

    result = client.invoke("greet", 2.0, name: "Alice")

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

    result = client.invoke("greet", 2.0, "Hello", name: "Alice")

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

    result = client.invoke("null", 2.0)

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

    result = client.invoke("noop", 2.0)

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

    result = client.invoke("work", 2.0)

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

    result = client.invoke("symbolize", 2.0)

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

    result = client.invoke("echo", 2.0, data)

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

    result = client.invoke("risky", 2.0)

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
      client.invoke("boom", 2.0)
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
        [i, client.invoke("echo", 2.0, i)]
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
        [i, client.invoke("double", 2.0, i)]
      end
    end

    negates = 3.times.map do |i|
      Thread.new do
        [i, client.invoke("negate", 2.0, i)]
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
