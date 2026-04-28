# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::Mysql2Test < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  setup do
    @db = Mysql2::Client.new(
      host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
      username: ENV.fetch("MYSQL_USERNAME", "root"),
      password: ENV.fetch("MYSQL_PASSWORD", "")
    )

    @sink = Aikido::Zen::Sinks::Mysql2::SINK
  end

  test "scans queries via #query" do
    mock = Minitest::Mock.new
    mock.expect :call, nil,
      query: String,
      dialect: :mysql,
      sink: @sink,
      operation: "query",
      context: Aikido::Zen::Context

    mock.expect :skips_on_nil_context?, true

    @sink.stub :scanners, [mock] do
      @db.query("SELECT 1")
    end

    assert_mock mock
  end

  test "fails when detecting an injection" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    assert_attack Aikido::Zen::Attacks::SQLInjectionAttack do
      @db.query "SELECT 1 WHERE 1 = '1' OR ''='';--'"
    end
  end

  test "doesn't fail when the user input is properly escaped" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    refute_attack do
      @db.query "SELECT 1 WHERE 1 = '1'' OR ''''='''';--'"
    end
  end

  class IDORTest < ActiveSupport::TestCase
    def with_mocked_protector(params = [])
      mock = Minitest::Mock.new
      mock.expect(:protect, nil, [String, :mysql, params, Aikido::Zen::Context])

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
      @db = Mysql2::Client.new(
        host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
        username: ENV.fetch("MYSQL_USERNAME", "root"),
        password: ENV.fetch("MYSQL_PASSWORD", "")
      )

      Aikido::Zen.config.idor_protection_enabled = true
    end

    test "#query includes IDOR protection" do
      with_mocked_protector do
        @db.query("SELECT 1")
      end
    end

    test "#prepare and #execute includes IDOR protection" do
      with_mocked_protector([1]) do
        statement = @db.prepare("SELECT ?")
        statement.execute(1)
      end
    end

    test "IDOR protection is triggered by complete example" do
      Aikido::Zen.config.idor_protection_enabled = true
      Aikido::Zen.config.idor_tenant_column_name = "tenant_id"
      Aikido::Zen.config.idor_excluded_table_names = ["roles"]

      Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
        Rack::MockRequest.env_for("/")
      )

      Aikido::Zen.enable_idor_protection
      Aikido::Zen.set_tenant_id(1)

      err = assert_raises(Aikido::Zen::IDOR::Error) do
        @db.query("SELECT * FROM users WHERE name = 'John'")
      end

      assert_equal "Zen IDOR protection: query on table 'users' is missing column 'tenant_id'", err.message
    end
  end
end
