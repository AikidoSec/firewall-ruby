# frozen_string_literal: true

require "test_helper"

require "sqlite3"
require "aikido/firewall/sinks/sqlite3"

class Aikido::Firewall::Sinks::SQLite3Test < Minitest::Test
  def setup
    @db = SQLite3::Database.new(":memory:")
  end

  def with_mocked_scanner(&b)
    mock = Minitest::Mock.new
    mock.expect :scan, nil, [String], dialect: :sqlite

    Aikido::Firewall::Vulnerabilities.stub_const(:SQLInjectionScanner, mock) do
      yield mock
    end
  end

  test "scans queries via #execute" do
    with_mocked_scanner do |mock|
      @db.execute("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #execute2" do
    with_mocked_scanner do |mock|
      @db.execute2("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #execute_batch" do
    with_mocked_scanner do |mock|
      @db.execute_batch("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries via #execute_batch2" do
    with_mocked_scanner do |mock|
      @db.execute_batch2("SELECT 1")

      assert_mock mock
    end
  end

  test "scans queries made by a prepared statement" do
    with_mocked_scanner do |mock|
      @db.prepare("SELECT 1") do |statement|
        statement.execute

        assert_mock mock
      end
    end
  end
end
