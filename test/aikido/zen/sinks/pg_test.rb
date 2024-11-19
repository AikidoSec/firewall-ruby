# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::PGTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  setup do
    @db = PG.connect(
      host: ENV.fetch("POSTGRES_HOST", "127.0.0.1"),
      user: ENV.fetch("POSTGRES_USERNAME", ENV["USER"]),
      password: ENV.fetch("POSTGRES_PASSWORD", "password"),
      dbname: ENV.fetch("POSTGRES_DATABASE", "postgres")
    )

    @sink = Aikido::Zen::Sinks::PG::SINK
  end

  def with_mocked_scanner(for_operation:, &b)
    mock = Minitest::Mock.new
    mock.expect :call, nil,
      query: String,
      dialect: :postgresql,
      sink: @sink,
      operation: for_operation,
      context: Aikido::Zen::Context

    @sink.stub :scanners, [mock] do
      yield mock
    end
  end

  test "scans queries via #send_query" do
    with_mocked_scanner for_operation: :send_query do |mock|
      @db.send_query("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #exec" do
    with_mocked_scanner for_operation: :exec do |mock|
      @db.exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #sync_exec" do
    with_mocked_scanner for_operation: :sync_exec do |mock|
      @db.sync_exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #async_exec" do
    with_mocked_scanner for_operation: :async_exec do |mock|
      @db.async_exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #send_query_params" do
    with_mocked_scanner for_operation: :send_query_params do |mock|
      @db.send_query_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #exec_params" do
    with_mocked_scanner for_operation: :exec_params do |mock|
      @db.exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #sync_exec_params" do
    with_mocked_scanner for_operation: :sync_exec_params do |mock|
      @db.sync_exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #async_exec_params" do
    with_mocked_scanner for_operation: :async_exec_params do |mock|
      @db.async_exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #send_prepare" do
    with_mocked_scanner for_operation: :send_prepare do |mock|
      @db.send_prepare("name", "SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #prepare" do
    with_mocked_scanner for_operation: :prepare do |mock|
      @db.prepare("name", "SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #async_prepare" do
    with_mocked_scanner for_operation: :async_prepare do |mock|
      @db.async_prepare("name", "SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #sync_prepare" do
    with_mocked_scanner for_operation: :sync_prepare do |mock|
      @db.sync_prepare("name", "SELECT 1")

      assert_mock mock
    end
  end

  test "fails when detecting an injection" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    assert_attack Aikido::Zen::Attacks::SQLInjectionAttack do
      @db.send_query "SELECT 1 WHERE 1 = '1' OR ''='';--'"
    end
  end

  test "doesn't fail when the user input is properly escaped" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    refute_attack do
      @db.send_query "SELECT 1 WHERE 1 = '1'' OR ''''='''';--'"
    end
  end
end
