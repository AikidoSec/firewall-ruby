# frozen_string_literal: true

require "test_helper"
require "timeout"

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

class Aikido::Zen::IPC::ServerTest < ActiveSupport::TestCase
  include IPCHelpers

  test "#initialize binds to 127.0.0.1 on a free port" do
    server = build_ipc_server

    assert_equal "127.0.0.1", server.host
    assert_operator server.port, :>, 0
  ensure
    server.close
  end

  test "#start raises ArgumentError when called without a block" do
    server = build_ipc_server

    err = assert_raises(ArgumentError) { server.start }
    assert_equal "block required", err.message
  ensure
    server.close
  end

  test "#start returns true when not running" do
    server = build_ipc_server

    assert_equal true, server.start {}
  ensure
    server.stop
  end

  test "#start returns false when running" do
    server = start_ipc_server {}

    assert_equal false, server.start {}
  ensure
    server.stop
  end

  test "#stop returns true when running" do
    server = start_ipc_server {}

    assert_equal true, server.stop
  end

  test "#stop returns false when not running" do
    server = build_ipc_server

    assert_equal false, server.stop
  ensure
    server.close
  end

  test "#stop yields the block when running" do
    server = start_ipc_server {}

    yielded = false
    server.stop { yielded = true }

    assert yielded
  end

  test "#stop does not yield the block when not running" do
    server = build_ipc_server

    yielded = false
    server.stop { yielded = true }

    refute yielded
  ensure
    server.close
  end
end

class Aikido::Zen::IPC::ClientTest < ActiveSupport::TestCase
  include IPCHelpers

  setup do
    @server = start_ipc_server {}
  end

  teardown do
    @server.stop
  end

  test "#initialize connects to the given host and port" do
    client = build_ipc_client(@server)

    addr = client.socket.remote_address

    assert_equal @server.host, addr.ip_address
    assert_equal @server.port, addr.ip_port
  ensure
    client.close
  end

  test "#start raises ArgumentError when called without a block" do
    client = build_ipc_client(@server)

    err = assert_raises(ArgumentError) { client.start }
    assert_equal "block required", err.message
  ensure
    client.close
  end

  test "#start returns true when not running" do
    client = build_ipc_client(@server)

    assert_equal true, client.start {}
  ensure
    client.stop
  end

  test "#start returns false when running" do
    gate = Concurrent::CountDownLatch.new(1)

    client = start_ipc_client(@server) { gate.wait }

    assert_equal false, client.start {}
  ensure
    gate.count_down
  end

  test "#stop returns true when running" do
    gate = Concurrent::CountDownLatch.new(1)

    client = start_ipc_client(@server) { gate.wait }

    assert_equal true, client.stop
  ensure
    gate.count_down
  end

  test "#stop returns false when not running" do
    client = build_ipc_client(@server)

    assert_equal false, client.stop
  ensure
    client.close
  end

  test "#stop yields the block when running" do
    gate = Concurrent::CountDownLatch.new(1)

    client = start_ipc_client(@server) { gate.wait }

    yielded = false
    client.stop { yielded = true }

    assert yielded
  ensure
    gate.count_down
  end

  test "#stop does not yield the block when not running" do
    client = build_ipc_client(@server)

    yielded = false
    client.stop { yielded = true }

    refute yielded
  ensure
    client.close
  end
end

class Aikido::Zen::IPC::ConnectionTest < ActiveSupport::TestCase
  include IPCHelpers

  test "client connects successfully when the shared secret matches" do
    connected = Queue.new

    server = start_ipc_server { connected.push(:ok) }

    client = build_ipc_client(server)

    assert_equal :ok, Timeout.timeout(2) { connected.pop }
  ensure
    client.close
    server.stop
  end

  test "client raises Handshake::Error and the server block is never called when the secret is wrong" do
    connected = Queue.new

    server = start_ipc_server { connected.push(:ok) }

    assert_raises(Aikido::Zen::IPC::Handshake::Error) do
      build_ipc_client(server, "wrong...wrong...wrong...wrong...")
    end

    assert_empty connected, "server block should not have been called"
  ensure
    server.stop
  end

  test "server continues accepting connections after a handshake rejection" do
    connected = Queue.new

    server = start_ipc_server { connected.push(:ok) }

    assert_raises(Aikido::Zen::IPC::Handshake::Error) do
      build_ipc_client(server, "wrong...wrong...wrong...wrong...")
    end

    client = build_ipc_client(server)

    assert_equal :ok, Timeout.timeout(2) { connected.pop }
  ensure
    client.close
    server.stop
  end

  test "server handles multiple sequential connections from different clients" do
    connected = Queue.new

    server = start_ipc_server { connected.push(:ok) }

    3.times do
      client = build_ipc_client(server)
      client.close
    end

    results = Timeout.timeout(2) do
      Array.new(3) { connected.pop }
    end

    assert_equal [:ok, :ok, :ok], results
  ensure
    server.stop
  end

  test "server handles multiple concurrent connections from different clients" do
    connected = Queue.new

    gate = Concurrent::CountDownLatch.new(1)

    server = start_ipc_server do
      connected.push(:ok)
      gate.wait
    end

    threads = 3.times.map do
      Thread.new do
        client = build_ipc_client(server)
        client.close
      end
    end

    results = Timeout.timeout(2) do
      Array.new(3) { connected.pop }
    end

    assert_equal [:ok, :ok, :ok], results
  ensure
    gate.count_down

    threads.each { |thread| thread.join(1) }

    server.stop
  end

  test "server continues accepting connections after a client disconnects abruptly" do
    connected = Queue.new

    server = start_ipc_server { connected.push(:ok) }

    client1 = build_ipc_client(server)
    Timeout.timeout(2) { connected.pop }

    client1.socket.close # disconnect abruptly

    client2 = build_ipc_client(server)

    assert_equal :ok, Timeout.timeout(2) { connected.pop }
  ensure
    client2.close
    server.stop
  end

  test "server continues accepting connections after the block raises" do
    connected = Queue.new

    server = start_ipc_server do
      Thread.current.report_on_exception = false

      connected.push(:attempted)
      raise "something went wrong"
    end

    client1 = build_ipc_client(server)
    Timeout.timeout(2) { connected.pop }

    client2 = build_ipc_client(server)

    assert_equal :attempted, Timeout.timeout(2) { connected.pop }
  ensure
    client1.close
    client2.close
    server.stop
  end

  test "#stop causes subsequent connection attempts to fail" do
    server = start_ipc_server {}
    server.stop

    assert_raises(Errno::ECONNREFUSED, Errno::ETIMEDOUT) do
      build_ipc_client(server)
    end
  end

  test "the client can write data to the server" do
    received = Queue.new

    server = start_ipc_server do |socket|
      data = socket.read(5)
      received.push(data)
    end

    client = build_ipc_client(server)

    client.socket.write("hello")

    assert_equal "hello", Timeout.timeout(2) { received.pop }
  ensure
    client.close
    server.stop
  end

  test "the server can write data to the client" do
    server = start_ipc_server { |socket| socket.write("hello") }

    client = build_ipc_client(server)

    assert_equal "hello", client.socket.read(5)
  ensure
    client.close
    server.stop
  end
end

class Aikido::Zen::IPC::FramedIOTest < ActiveSupport::TestCase
  include Aikido::Zen::IPC::FramedIO

  def socket_pair
    Socket.pair(:UNIX, :STREAM, 0)
  end

  test "#read_frame_with_timeout raises FrameTooLargeError when the frame exceeds max_size" do
    reader, writer = socket_pair

    writer.write([10].pack("N")) # declare a 10-byte frame

    err = assert_raises(Aikido::Zen::IPC::FramedIO::FrameTooLargeError) do
      read_frame_with_timeout(reader, 4, 1)
    end

    assert_equal "frame too large: 10 bytes (max: 4)", err.message
  ensure
    reader.close
    writer.close
  end

  test "#write_frame_with_timeout raises FrameTooLargeError when the frame exceeds max_size" do
    reader, writer = socket_pair

    err = assert_raises(Aikido::Zen::IPC::FramedIO::FrameTooLargeError) do
      write_frame_with_timeout(writer, "hello world", 5, 1)
    end
    assert_equal "frame too large: 11 bytes (max: 5)", err.message
  ensure
    reader.close
    writer.close
  end

  test "handles large frames correctly" do
    reader, writer = socket_pair

    data = SecureRandom.bytes(1 * 1024 * 1024)

    thread = Thread.new { write_frame_with_timeout(writer, data, nil, 5) }
    result = read_frame_with_timeout(reader, nil, 5)
    thread.join

    assert_equal data, result
  ensure
    reader.close
    writer.close
  end
end

class Aikido::Zen::IPC::HandshakeTest < ActiveSupport::TestCase
  CHALLENGE_LEN = Aikido::Zen::IPC::Handshake::CHALLENGE_LEN
  HMAC_LEN = Aikido::Zen::IPC::Handshake::HMAC_LEN

  def socket_pair
    Socket.pair(:UNIX, :STREAM, 0)
  end

  def build_ipc_server
    Object.new.extend(Aikido::Zen::IPC::Handshake::Server)
  end

  def build_ipc_client
    Object.new.extend(Aikido::Zen::IPC::Handshake::Client)
  end

  def build_server_handshake_thread(socket, secret = Aikido::Zen.secret)
    server = build_ipc_server

    thread = Thread.new { server.send(:handshake, socket, secret) }
    thread.report_on_exception = false
    thread
  end

  def build_client_handshake_thread(socket, secret = Aikido::Zen.secret)
    client = build_ipc_client

    thread = Thread.new { client.send(:handshake, socket, secret) }
    thread.report_on_exception = false
    thread
  end

  test "Handshake completes successfully with a matching secret" do
    server_socket, client_socket = socket_pair

    server_thread = build_server_handshake_thread(server_socket)
    client_thread = build_client_handshake_thread(client_socket)

    assert_nothing_raised { server_thread.value }
    assert_nothing_raised { client_thread.value }
  ensure
    server_socket.close
    client_socket.close
  end

  test "Handshake::Server#handshake raises Handshake::Error on timeout" do
    server_socket, client_socket = socket_pair

    server = build_ipc_server

    err = assert_raises(Aikido::Zen::IPC::Handshake::Error) do
      server.send(:handshake, server_socket, Aikido::Zen.secret, 0)
    end

    assert_equal "handshake timed out", err.message
  ensure
    server_socket.close
    client_socket.close
  end

  test "Handshake::Client#handshake raises Handshake::Error on timeout" do
    server_socket, client_socket = socket_pair

    client = build_ipc_client

    err = assert_raises(Aikido::Zen::IPC::Handshake::Error) do
      client.send(:handshake, client_socket, Aikido::Zen.secret, 0)
    end

    assert_equal "handshake timed out", err.message
  ensure
    server_socket.close
    client_socket.close
  end

  test "Handshake::Server#handshake raises Handshake::Error when the connection closes" do
    server_socket, client_socket = socket_pair

    thread = build_server_handshake_thread(server_socket)

    client_socket.close

    err = assert_raises(Aikido::Zen::IPC::Handshake::Error) { thread.value }
    assert_equal "connection closed", err.message
  ensure
    server_socket.close
    client_socket.close
  end

  test "Handshake::Client#handshake raises Handshake::Error when the connection closes" do
    server_socket, client_socket = socket_pair

    thread = build_client_handshake_thread(client_socket)

    server_socket.close

    err = assert_raises(Aikido::Zen::IPC::Handshake::Error) { thread.value }
    assert_equal "connection closed", err.message
  ensure
    server_socket.close
    client_socket.close
  end

  test "Handshake::Server#handshake raises Handshake::Error when the client sends a wrong HMAC" do
    server_socket, client_socket = socket_pair

    thread = build_server_handshake_thread(server_socket)

    _server_challenge = client_socket.read(CHALLENGE_LEN)
    client_socket.write(SecureRandom.bytes(HMAC_LEN + CHALLENGE_LEN)) # garbage client HMAC and challenge

    err = assert_raises(Aikido::Zen::IPC::Handshake::Error) { thread.value }
    assert_equal "client authentication failed", err.message
  ensure
    server_socket.close
    client_socket.close
  end

  test "Handshake::Client#handshake raises Handshake::Error when the server sends a wrong HMAC" do
    server_socket, client_socket = socket_pair

    thread = build_client_handshake_thread(client_socket)

    server_challenge = SecureRandom.bytes(CHALLENGE_LEN)
    server_socket.write(server_challenge)
    _client_hmac_and_challenge = server_socket.read(HMAC_LEN + CHALLENGE_LEN)
    server_socket.write(SecureRandom.bytes(HMAC_LEN)) # garbage server HMAC

    err = assert_raises(Aikido::Zen::IPC::Handshake::Error) { thread.value }
    assert_equal "server authentication failed", err.message
  ensure
    server_socket.close
    client_socket.close
  end
end
