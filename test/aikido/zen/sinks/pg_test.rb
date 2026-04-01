# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::PGTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  setup do
    @db = PG.connect(
      host: ENV.fetch("POSTGRES_HOST", "127.0.0.1"),
      user: ENV.fetch("POSTGRES_USERNAME", "postgres"),
      password: ENV.fetch("POSTGRES_PASSWORD", "password"),
      dbname: ENV.fetch("POSTGRES_DATABASE", "postgres")
    )

    @sink = Aikido::Zen::Sinks::PG::SINK
  end

  def with_mocked_scanner(for_operation:, &blk)
    mock = Minitest::Mock.new
    mock.expect(
      :call, nil,
      query: String,
      dialect: :postgresql,
      scan: Aikido::Zen::Scan,
      sink: @sink,
      operation: for_operation,
      context: Aikido::Zen::Context
    )

    mock.expect :skips_on_nil_context?, true

    @sink.stub :scanners, [mock] do
      yield mock
    end
  end

  test "scans queries via #send_query" do
    with_mocked_scanner for_operation: :send_query do |mock|
      @db.send_query("SELECT 1")
      while @db.get_result; end

      assert_mock mock
    end
  end

  test "scans queries via #exec" do
    with_mocked_scanner for_operation: :exec do |mock|
      @db.exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #async_exec" do
    with_mocked_scanner for_operation: :async_exec do |mock|
      @db.async_exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #sync_exec" do
    with_mocked_scanner for_operation: :sync_exec do |mock|
      @db.sync_exec("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #send_query_params" do
    with_mocked_scanner for_operation: :send_query_params do |mock|
      @db.send_query_params("SELECT $1", ["1"])
      while @db.get_result; end

      assert_mock mock
    end
  end

  test "scans queries via #exec_params" do
    with_mocked_scanner for_operation: :exec_params do |mock|
      @db.exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #async_exec_params" do
    with_mocked_scanner for_operation: :async_exec_params do |mock|
      @db.async_exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #sync_exec_params" do
    with_mocked_scanner for_operation: :sync_exec_params do |mock|
      @db.sync_exec_params("SELECT $1", ["1"])

      assert_mock mock
    end
  end

  test "scans queries via #send_prepare and #exec_prepared" do
    @db.send_prepare("name", "SELECT 1")
    while @db.get_result; end

    with_mocked_scanner for_operation: :exec_prepared do |mock|
      @db.exec_prepared("name")

      assert_mock mock
    end
  end

  test "scans queries via #send_prepare and #async_exec_prepared" do
    @db.send_prepare("name", "SELECT 1")
    while @db.get_result; end

    with_mocked_scanner for_operation: :async_exec_prepared do |mock|
      @db.async_exec_prepared("name")

      assert_mock mock
    end
  end

  test "scans queries via #send_prepare and #sync_exec_prepared" do
    @db.send_prepare("name", "SELECT 1")
    while @db.get_result; end

    with_mocked_scanner for_operation: :sync_exec_prepared do |mock|
      @db.sync_exec_prepared("name")

      assert_mock mock
    end
  end

  test "scans queries via #prepare and #exec_prepared" do
    @db.prepare("name", "SELECT 1")

    with_mocked_scanner for_operation: :exec_prepared do |mock|
      @db.exec_prepared("name")

      assert_mock mock
    end
  end

  test "scans queries via #prepare and #async_exec_prepared" do
    @db.prepare("name", "SELECT 1")

    with_mocked_scanner for_operation: :async_exec_prepared do |mock|
      @db.async_exec_prepared("name")

      assert_mock mock
    end
  end

  test "scans queries via #prepare and #sync_exec_prepared" do
    @db.prepare("name", "SELECT 1")

    with_mocked_scanner for_operation: :sync_exec_prepared do |mock|
      @db.sync_exec_prepared("name")

      assert_mock mock
    end
  end

  test "scans queries via #sync_prepare and #exec_prepared" do
    @db.sync_prepare("name", "SELECT 1")

    with_mocked_scanner for_operation: :exec_prepared do |mock|
      @db.exec_prepared("name")

      assert_mock mock
    end
  end

  test "scans queries via #sync_prepare and #async_exec_prepared" do
    @db.sync_prepare("name", "SELECT 1")

    with_mocked_scanner for_operation: :async_exec_prepared do |mock|
      @db.async_exec_prepared("name")

      assert_mock mock
    end
  end

  test "scans queries via #sync_prepare and #sync_exec_prepared" do
    @db.sync_prepare("name", "SELECT 1")

    with_mocked_scanner for_operation: :sync_exec_prepared do |mock|
      @db.sync_exec_prepared("name")

      assert_mock mock
    end
  end

  test "fails when detecting an injection" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    assert_attack Aikido::Zen::Attacks::SQLInjectionAttack do
      @db.send_query "SELECT 1 WHERE 1 = '1' OR ''='';--'"
      while @db.get_result; end
    end
  end

  test "doesn't fail when the user input is properly escaped" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    refute_attack do
      @db.send_query "SELECT 1 WHERE 1 = '1'' OR ''''='''';--'"
      while @db.get_result; end
    end
  end

  class IDORTest < ActiveSupport::TestCase
    def with_mocked_protector(params = [])
      mock = Minitest::Mock.new
      mock.expect(:protect, nil, [String, :postgresql, params, Aikido::Zen::Context])

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
      @db = PG.connect(
        host: ENV.fetch("POSTGRES_HOST", "127.0.0.1"),
        user: ENV.fetch("POSTGRES_USERNAME", "postgres"),
        password: ENV.fetch("POSTGRES_PASSWORD", "password"),
        dbname: ENV.fetch("POSTGRES_DATABASE", "postgres")
      )

      Aikido::Zen.config.idor_protection_enabled = true
    end

    test "#send_query includes IDOR protection" do
      with_mocked_protector do
        @db.send_query("SELECT 1")
        while @db.get_result; end
      end
    end

    test "#exec includes IDOR protection" do
      with_mocked_protector do
        @db.exec("SELECT 1")
      end
    end

    test "#async_exec includes IDOR protection" do
      with_mocked_protector do
        @db.async_exec("SELECT 1")
      end
    end

    test "#sync_exec includes IDOR protection" do
      with_mocked_protector do
        @db.sync_exec("SELECT 1")
      end
    end

    test "#send_query_params includes IDOR protection" do
      with_mocked_protector([1]) do
        @db.send_query_params("SELECT $1", [1])
        while @db.get_result; end
      end
    end

    test "#exec_params includes IDOR protection" do
      with_mocked_protector([1]) do
        @db.exec_params("SELECT $1", [1])
      end
    end

    test "#async_exec_params includes IDOR protection" do
      with_mocked_protector([1]) do
        @db.async_exec_params("SELECT $1", [1])
      end
    end

    test "#sync_exec_params includes IDOR protection" do
      with_mocked_protector([1]) do
        @db.sync_exec_params("SELECT $1", [1])
      end
    end

    [
      :send_prepare,
      :prepare,
      :sync_prepare
    ].each do |prepare_method_name|
      [
        :send_query_prepared,
        :exec_prepared,
        :sync_exec_prepared
      ].each do |exec_method_name|
        test "##{prepare_method_name} and ##{exec_method_name} includes IDOR protection" do
          sql = "SELECT $1"

          name = "name_for_#{prepare_method_name}_and_#{exec_method_name}"

          @db.send(prepare_method_name, name, sql)
          if prepare_method_name == :send_prepare
            while @db.get_result; end
          end

          assert_equal sql, @db.aikido_idor_prepared_statements[name]

          with_mocked_protector([1]) do
            @db.send(exec_method_name, name, [1])
            if exec_method_name == :send_query_prepared
              while @db.get_result; end
            end
          end
        end
      end
    end
  end
end
