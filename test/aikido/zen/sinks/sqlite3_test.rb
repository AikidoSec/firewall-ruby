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

    mock.expect :skips_on_nil_context?, false

    @sink.stub(:scanners, [mock]) do
      yield mock
    end
  end

  test "scans queries via #execute" do
    with_mocked_scanner for_operation: "database.execute" do |mock|
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
    with_mocked_scanner for_operation: "database.execute" do |mock|
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
      end

      assert_mock mock
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

  class IDORTest < ActiveSupport::TestCase
    def with_mocked_protector(params = [])
      mock = Minitest::Mock.new
      mock.expect(:protect, nil, [String, :sqlite, params, 1])

      original_protector = Aikido::Zen.instance_variable_get(:@idor_protector)
      Aikido::Zen.instance_variable_set(:@idor_protector, mock)

      Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
        Rack::MockRequest.env_for("/")
      )

      Aikido::Zen.set_tenant_id(1)

      yield

      assert_mock mock
    ensure
      Aikido::Zen.instance_variable_set(:@idor_protector, original_protector)
    end

    setup do
      @db = SQLite3::Database.new(":memory:")

      Aikido::Zen.enable_idor_protection
    end

    test "#execute includes IDOR protection" do
      with_mocked_protector do
        @db.execute("SELECT 1")
      end
    end

    test "#execute_batch includes IDOR protection" do
      with_mocked_protector do
        @db.execute_batch("SELECT 1")
      end
    end

    test "#execute_batch2 includes IDOR protection" do
      with_mocked_protector do
        @db.execute_batch2("SELECT 1")
      end
    end

    test "#prepare and #execute with block includes IDOR protection" do
      with_mocked_protector([1]) do
        @db.prepare("SELECT ?") do |statement|
          statement.execute(1)
        end
      end
    end

    test "#prepare and #execute without block includes IDOR protection" do
      with_mocked_protector([1]) do
        statement = @db.prepare("SELECT ?")
        statement.execute(1)
      end
    end
  end
end
