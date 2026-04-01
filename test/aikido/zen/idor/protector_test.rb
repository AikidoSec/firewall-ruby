# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::IDOR::ProtectorTest < ActiveSupport::TestCase
  module GenericTest
    extend ActiveSupport::Testing::Declarative

    def refute_idor
      Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
        Rack::MockRequest.env_for("/")
      )

      Aikido::Zen.enable_idor_protection
      Aikido::Zen.set_tenant_id(1)

      assert_silent do
        yield
      end
    end

    def assert_idor
      Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
        Rack::MockRequest.env_for("/")
      )

      Aikido::Zen.enable_idor_protection
      Aikido::Zen.set_tenant_id(1)

      assert_raises(Aikido::Zen::IDOR::Error) do
        yield
      end
    end

    test "IDOR protection is not triggered if a context is not set" do
      assert_nil Aikido::Zen.current_context

      Aikido::Zen.enable_idor_protection
      Aikido::Zen.set_tenant_id(1)

      assert_silent do
        exec("SELECT * FROM users WHERE tenant_id = 1")
      end
    end

    test "IDOR protection is triggered if the tenant ID is not set" do
      Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
        Rack::MockRequest.env_for("/")
      )

      Aikido::Zen.enable_idor_protection

      err = assert_raises(Aikido::Zen::IDOR::Error) do
        exec("SELECT * FROM users WHERE tenant_id = 1")
      end

      assert_equal "Zen IDOR protection: Aikido::Zen.set_tenant_id was not called for this request. Every request must have a tenant ID when IDOR protection is enabled.", err.message
    end

    test "IDOR protection is triggered for SELECT queries if the tenant ID column does not match the configured tenant ID" do
      err = assert_idor do
        exec("SELECT * FROM users WHERE tenant_id = 2")
      end

      assert_equal "Zen IDOR protection: query on table 'users' sets 'tenant_id' to '2' but tenant ID is '1'", err.message
    end

    test "IDOR protection is triggered for INSERT queries if the tenant ID column does not match the configured tenant ID" do
      err = assert_idor do
        exec("INSERT INTO users (name, tenant_id) VALUES ('John', 2)")
      end

      assert_equal "Zen IDOR protection: INSERT on table 'users' sets 'tenant_id' to '2' but tenant ID is '1'", err.message
    end

    test "IDOR protection is not triggered for SELECT queries if the table name is is in the list of excluded table names" do
      refute_idor do
        exec("SELECT * FROM roles WHERE name = 'staff'")
      end
    end

    test "IDOR protection is not triggered for INSERT queries if the table name is is in the list of excluded table names" do
      refute_idor do
        exec("INSERT INTO roles (name) VALUES ('staff')")
      end
    end

    test "IDOR protection is triggered if IDOR analyss fails" do
      err = assert_idor do
        exec("THIS IS NOT SQL")
      end

      assert_equal "Zen IDOR protection: sql parser error: Expected: an SQL statement, found: THIS at Line: 1, Column: 1", err.message
    end

    test "IDOR protection is not triggered for SELECT queries if the query has a placeholder that could not be resolved" do
      err = assert_idor do
        exec("SELECT * FROM users AS u WHERE u.tenant_id = $1")
      end

      assert_equal "Zen IDOR protection: query on table 'users' has a placeholder for 'tenant_id' that could not be resolved", err.message
    end

    # IDOR protection is/is not triggered if the tenant ID column is not/is present

    test "IDOR protection is not triggered for SELECT queries if the tenant ID column is present" do
      refute_idor do
        exec("SELECT * FROM users WHERE name = $1 AND tenant_id = $2", ["John", 1])
      end
    end

    test "IDOR protection is triggered for SELECT queries if the tenant ID column is not present" do
      assert_idor do
        exec("SELECT * FROM users WHERE name = $1", ["John"])
      end
    end

    test "IDOR protection is not triggered for UPDATE queries if the tenant ID column is present" do
      refute_idor do
        exec("UPDATE users SET name = $1 WHERE tenant_id = $2", ["John", 1])
      end
    end

    test "IDOR protection is triggered for UPDATE queries if the tenant ID column is not present" do
      assert_idor do
        exec("UPDATE users SET name = $1", ["John"])
      end
    end

    test "IDOR protection is not triggered for DELETE queries if the tenant ID column is present" do
      refute_idor do
        exec("DELETE FROM users WHERE name = $1 AND tenant_id = $2", ["John", 1])
      end
    end

    test "IDOR protection is triggered for DELETE queries if the tenant ID column is not present" do
      assert_idor do
        exec("DELETE FROM users WHERE name = $1", ["John"])
      end
    end

    test "IDOR protection is not triggered for INSERT queries if the tenant ID column is present" do
      refute_idor do
        exec("INSERT INTO users (name, tenant_id) VALUES ('John', $1)", [1])
      end
    end

    test "IDOR protection is triggered for INSERT queries if the tenant ID column is not present" do
      assert_idor do
        exec("INSERT INTO users (name) VALUES ('John')")
      end
    end

    test "IDOR protection is triggered for INSERT queries without insert columns if the tenant ID column is not present" do
      err = assert_idor do
        exec("INSERT INTO other SELECT * FROM users WHERE tenant_id = $1", [1])
      end

      assert_equal "Zen IDOR protection: INSERT on table 'other' is missing column 'tenant_id'", err.message
    end

    # IDOR protection is triggered if the query has a placeholder that could not be resolved

    test "IDOR protection is triggered for SELECT queries if the query has a placeholder that could not be resolved" do
      err = assert_idor do
        exec("SELECT * FROM users WHERE name = $1 AND tenant_id = $2")
      end

      assert_equal "Zen IDOR protection: query on table 'users' has a placeholder for 'tenant_id' that could not be resolved", err.message
    end

    test "IDOR protection is triggered for UPDATE queries if the query has a placeholder that could not be resolved" do
      err = assert_idor do
        exec("UPDATE users SET name = $1 WHERE tenant_id = $2")
      end

      assert_equal "Zen IDOR protection: query on table 'users' has a placeholder for 'tenant_id' that could not be resolved", err.message
    end

    test "IDOR protection is triggered for DELETE queries if the query has a placeholder that could not be resolved" do
      err = assert_idor do
        exec("DELETE FROM users WHERE name = $1 AND tenant_id = $2")
      end

      assert_equal "Zen IDOR protection: query on table 'users' has a placeholder for 'tenant_id' that could not be resolved", err.message
    end

    test "IDOR protection is triggered for INSERT queries if the query has a placeholder that could not be resolved" do
      err = assert_idor do
        exec("INSERT INTO users (name, tenant_id) VALUES ('John', $1)")
      end

      assert_equal "Zen IDOR protection: INSERT on table 'users' has a placeholder for 'tenant_id' that could not be resolved", err.message
    end

    test "IDOR protection is triggered for INSERT queries without insert columns if the query has a placeholder that could not be resolved" do
      err = assert_idor do
        exec("INSERT INTO other SELECT * FROM users WHERE tenant_id = $1")
      end

      assert_equal "Zen IDOR protection: query on table 'users' has a placeholder for 'tenant_id' that could not be resolved", err.message
    end

    test "IDOR analysis is cached upto Aikido::Zen.config.idor_max_cache_entries" do
      Aikido::Zen.config.idor_max_cache_entries = 3

      assert_equal 0, Aikido::Zen.idor_protector.cache.size

      Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
        Rack::MockRequest.env_for("/")
      )

      Aikido::Zen.enable_idor_protection

      Aikido::Zen.set_tenant_id(1)
      3.times { exec("SELECT * FROM users WHERE name = 'John' AND tenant_id = 1") }
      assert_equal 1, Aikido::Zen.idor_protector.cache.size

      Aikido::Zen.set_tenant_id(2)
      5.times { exec("SELECT * FROM users WHERE name = 'Jane' AND tenant_id = 2") }
      assert_equal 2, Aikido::Zen.idor_protector.cache.size

      Aikido::Zen.set_tenant_id(3)
      3.times { exec("SELECT * FROM users WHERE name = 'Alice' AND tenant_id = 3") }
      assert_equal 3, Aikido::Zen.idor_protector.cache.size

      Aikido::Zen.set_tenant_id(4)
      5.times { exec("SELECT * FROM users WHERE name = 'Bob' AND tenant_id = 4") }
      assert_equal 3, Aikido::Zen.idor_protector.cache.size
    end
  end

  class MySQLSQLDialectTest < ActiveSupport::TestCase
    include GenericTest

    def exec(sql, params = [])
      # Convert PostgreSQL-style placeholders to MySQL-style placeholders.
      sql = sql.gsub(/\$\d+/, "?")

      Aikido::Zen.idor_protect(sql, :mysql, params)
    end

    setup do
      Aikido::Zen.config.idor_protection_enabled = true
      Aikido::Zen.config.idor_tenant_column_name = "tenant_id"
      Aikido::Zen.config.idor_excluded_table_names = ["roles"]
    end
  end

  class PostgresSQLDialectTest < ActiveSupport::TestCase
    include GenericTest

    def exec(sql, params = [])
      Aikido::Zen.idor_protect(sql, :postgresql, params)
    end

    setup do
      Aikido::Zen.config.idor_protection_enabled = true
      Aikido::Zen.config.idor_tenant_column_name = "tenant_id"
      Aikido::Zen.config.idor_excluded_table_names = ["roles"]
    end
  end

  class SQLiteDialectTest < ActiveSupport::TestCase
    include GenericTest

    def exec(sql, params = [])
      # Convert PostgreSQL-style placeholders to SQLite-style placeholders.
      sql = sql.gsub(/\$\d+/, "?")

      Aikido::Zen.idor_protect(sql, :sqlite, params)
    end

    setup do
      Aikido::Zen.config.idor_protection_enabled = true
      Aikido::Zen.config.idor_tenant_column_name = "tenant_id"
      Aikido::Zen.config.idor_excluded_table_names = ["roles"]
    end
  end
end
