# frozen_string_literal: true

require "test_helper"

require "trilogy"
require "aikido/firewall/sinks/trilogy"

class Aikido::Firewall::Sinks::TrilogyTest < ActiveSupport::TestCase
  setup do
    @db = Trilogy.new(
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
