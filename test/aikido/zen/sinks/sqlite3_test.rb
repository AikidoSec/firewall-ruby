# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::SQLite3Test < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  setup do
    @db = SQLite3::Database.new(":memory:")
    @sink = Aikido::Zen::Sinks::SQLite3::SINK
  end

  def with_mocked_scanner(for_operation:, &b)
    mock = Minitest::Mock.new
    mock.expect :call, nil,
      query: String,
      dialect: :sqlite,
      sink: @sink,
      operation: for_operation,
      context: Aikido::Zen::Context

    @sink.stub(:scanners, [mock]) do
      yield mock
    end
  end

  test "scans queries via #execute" do
    with_mocked_scanner for_operation: "statement.execute" do |mock|
      @db.execute("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #execute2" do
    with_mocked_scanner for_operation: "statement.execute" do |mock|
      @db.execute2("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #execute_batch" do
    with_mocked_scanner for_operation: "statement.execute" do |mock|
      @db.execute_batch("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #execute_batch2" do
    with_mocked_scanner for_operation: "exec_batch" do |mock|
      @db.execute_batch2("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries made by a prepared statement" do
    with_mocked_scanner for_operation: "statement.execute" do |mock|
      @db.prepare("SELECT 1") do |statement|
        statement.execute

        assert_mock mock
      end
    end
  end

  test "fails when detecting an injection" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    assert_attack Aikido::Zen::Attacks::SQLInjectionAttack do
      @db.execute "SELECT 1 WHERE 1 = '1' OR ''='';--'"
    end
  end

  test "doesn't fail when the user input is properly escaped" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    refute_attack do
      @db.execute "SELECT 1 WHERE 1 = '1'' OR ''''='''';--'"
    end
  end
end
