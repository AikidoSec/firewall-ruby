# frozen_string_literal: true

require "test_helper"

require "pg"
require "aikido/firewall/sinks/pg"

class Aikido::Firewall::Sinks::PGTest < ActiveSupport::TestCase
  include StubsCurrentRequest

  setup do
    @db = PG.connect(
      host: ENV.fetch("POSTGRES_HOST", "127.0.0.1"),
      user: ENV.fetch("POSTGRES_USERNAME", ENV["USER"]),
      password: ENV.fetch("POSTGRES_PASSWORD", "password"),
      dbname: ENV.fetch("POSTGRES_DATABASE", "postgres")
    )

    @sink = Aikido::Firewall::Sinks::PG::SINK
  end

  def with_mocked_scanner(&b)
    mock = Minitest::Mock.new
    mock.expect :call, nil,
      query: String, dialect: :postgresql, sink: @sink, request: Aikido::Agent::Request

    @sink.stub :scanners, [mock] do
      yield mock
    end
  end

  test "scans queries via #send_query" do
    with_mocked_scanner do |mock|
      @db.send_query("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #exec" do
    with_mocked_scanner do |mock|
      @db.exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #sync_exec" do
    with_mocked_scanner do |mock|
      @db.sync_exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #async_exec" do
    with_mocked_scanner do |mock|
      @db.async_exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #send_query_params" do
    with_mocked_scanner do |mock|
      @db.send_query_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #exec_params" do
    with_mocked_scanner do |mock|
      @db.exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #sync_exec_params" do
    with_mocked_scanner do |mock|
      @db.sync_exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #async_exec_params" do
    with_mocked_scanner do |mock|
      @db.async_exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #send_prepare" do
    with_mocked_scanner do |mock|
      @db.send_prepare("name", "SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #prepare" do
    with_mocked_scanner do |mock|
      @db.prepare("name", "SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #asyncprepare" do
    with_mocked_scanner do |mock|
      @db.async_prepare("name", "SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #sync_prepare" do
    with_mocked_scanner do |mock|
      @db.sync_prepare("name", "SELECT 1")

      assert_mock mock
    end
  end
end
