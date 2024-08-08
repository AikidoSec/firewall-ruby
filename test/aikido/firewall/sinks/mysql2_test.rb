# frozen_string_literal: true

require "test_helper"

require "mysql2"
require "aikido/firewall/sinks/mysql2"

class Aikido::Firewall::Sinks::Mysql2Test < Minitest::Test
  setup do
    @db = Mysql2::Client.new(
      host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
      username: ENV.fetch("MYSQL_USERNAME", "root"),
      password: ENV.fetch("MYSQL_PASSWORD", "")
    )
  end

  test "scans queries via #query" do
    mock = Minitest::Mock.new
    mock.expect :scan, nil, [String], dialect: :mysql

    Aikido::Firewall::Vulnerabilities.stub_const(:SQLInjectionScanner, mock) do
      @db.query("SELECT 1")
    end

    assert_mock mock
  end
end
