# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::SQLInjectionScannerTest < ActiveSupport::TestCase
  module Assertions
    def assert_attack(query, input = query, dialect = :common, reason = "`#{input}` was not blocked (#{dialect})")
      assert scan(query, input, dialect), reason
    end

    def refute_attack(query, input = query, dialect = :common, reason = "`#{input}` was blocked (#{dialect})")
      refute scan(query, input, dialect), reason
    end

    def scan(query, input = query, dialect = :common)
      dialect = Aikido::Zen::Scanners::SQLInjectionScanner::DIALECTS.fetch(dialect)
      Aikido::Zen::Scanners::SQLInjectionScanner.new(query, input, dialect).attack?
    end
  end

  include Assertions

  def assert_attack(query, input = query, *args)
    super(query, input, :mysql, *args)
    super(query, input, :postgresql, *args)
    super(query, input, :sqlite, *args)
  end

  def refute_attack(query, input = query, *args)
    super(query, input, :mysql, *args)
    super(query, input, :postgresql, *args)
    super(query, input, :sqlite, *args)
  end

  test "ignores inputs longer than the query" do
    refute_attack "SELECT * FROM users", "SELECT * FROM users WHERE 1=1"
  end

  test "rejects input that contains SQL commands" do
    assert_attack "Roses are red insErt are blue"
    assert_attack "Roses are red cREATE are blue"
    assert_attack "Roses are red drop are blue"
    assert_attack "Roses are red updatE are blue"
    assert_attack "Roses are red SELECT are blue"
    assert_attack "Roses are red dataBASE are blue"
    assert_attack "Roses are red alter are blue"
    assert_attack "Roses are red grant are blue"
    assert_attack "Roses are red savepoint are blue"
    assert_attack "Roses are red commit are blue"
    assert_attack "Roses are red or blue"
    assert_attack "Roses are red and lovely"
    assert_attack "This is a group_concat_test"
  end

  test "rejects input with unescaped and unencapsulated special characters" do
    assert_attack "Termin;ate"
    assert_attack "Roses <> violets"
    assert_attack "Roses < Violets"
    assert_attack "Roses > Violets"
    assert_attack "Roses != Violets"

    assert_attack "UNTER;"
  end

  test "allows input with allowed escape sequences" do
    refute_attack "SELECT * FROM users WHERE id = '\nusers'", "\nusers"
    refute_attack "SELECT * FROM users WHERE id = '\rusers'", "\rusers"
    refute_attack "SELECT * FROM users WHERE id = '\tusers'", "\tusers"
  end

  # rubocop:disable Style/StringLiterals
  test "allows input with escaped quotes" do
    refute_attack %(SELECT * FROM comments WHERE comment = "I'm writting you"), "I'm writting you"
    refute_attack %(SELECT * FROM comments WHERE comment = "I`m writting you"), "I`m writting you"
    refute_attack %(SELECT * FROM comments WHERE comment = "I\\"m writting you"), "I\"m writting you"
    refute_attack %(SELECT * FROM comments WHERE comment = 'I"m writting you'), 'I"m writting you'
    refute_attack %(SELECT * FROM comments WHERE comment = 'I`m writting you'), 'I"m writting you'
    refute_attack %(SELECT * FROM comments WHERE comment = 'I\\'m writting you'), 'I\'m writting you'
    refute_attack %(SELECT * FROM comments WHERE comment = `I\\`m writting you`), "I`m writting you"
  end
  # rubocop:enable Style/StringLiterals

  test "allows quoted comments" do
    refute_attack "SELECT * FROM hashtags WHERE name = '#hashtag'", "#hashtag"
    refute_attack "SELECT * FROM hashtags WHERE name = '-- nope'", "-- nope"
  end

  test "allows comments at the end of the query" do
    skip <<~REASON
      Although this is valid and not dangerous, our algorithm isn't good enough
      to treat this properly yet. We can consider it an edge case, since users
      really shouldn't be adding comments to your SQL queries.
    REASON

    refute_attack "SELECT * FROM hashtags WHERE id = 1 -- Query by name", "-- Query by name"
  end

  test "allows some special characters and single character queries" do
    refute_attack "#"
    refute_attack "'"
  end

  test "allows SQL syntax when it is correctly encapsulated or is not dangerous" do
    refute_attack %("UNION;"), "UNION;"
    refute_attack %('UNION 123' UNION "UNION 123"), "UNION 123"

    # Input not present in query
    refute_attack %('union' is not UNION), "UNION!"

    # Dangerous chars, but encapsulated
    refute_attack %("COPY/*"), "COPY/*"
    refute_attack %('union' is not "UNION--"), "UNION--"

    refute_attack "SELECT * FROM table", "*"

    refute_attack "SELECT * FROM users WHERE id = 1", "SELECT"
  end

  test "handles multiline inputs" do
    refute_attack <<~QUERY.chomp, <<~INPUT.chomp
      SELECT * FROM users WHERE id = 'a
      b
      c';
    QUERY
      a
      b
      c
    INPUT

    assert_attack <<~QUERY.chomp, <<~INPUT.chomp
      SELECT * FROM users WHERE id = 'a'
      OR 1=1#'
    QUERY
      a'
      OR 1=1#
    INPUT
  end

  test "handles multiline queries" do
    assert_attack <<~QUERY.chomp, "1' OR 1=1"
      SELECT *
      FROM users
      WHERE id = '1' OR 1=1
    QUERY

    assert_attack <<~QUERY.chomp, "1' OR 1=1"
      SELECT *
      FROM users
      WHERE id = '1' OR 1=1
        AND is_escaped = '1'' OR 1=1'
    QUERY

    assert_attack <<~QUERY.chomp, "1' OR 1=1"
      SELECT *
      FROM users
      WHERE id = '1' OR 1=1
        AND is_escaped = "1' OR 1=1"
    QUERY

    refute_attack <<~QUERY.chomp, "123"
      SELECT * FROM `users`
      WHERE id = 123
    QUERY

    refute_attack <<~QUERY.chomp, "users"
      SELECT * FROM `us``ers`
      WHERE id = 123
    QUERY

    refute_attack <<~QUERY.chomp, "123"
      SELECT * FROM users
      WHERE id = 123
    QUERY

    refute_attack <<~QUERY.chomp, "123"
      SELECT * FROM users
      WHERE id = '123'
    QUERY

    refute_attack <<~QUERY.chomp, "1' OR 1=1"
      SELECT *
      FROM users
      WHERE is_escaped = "1' OR 1=1"
    QUERY
  end

  test "it does not flag safe keywords as attacks" do
    query = <<~SQL.chomp
      INSERT INTO businesses (
            business_id,
            created_at,
            updated_at,
            changed_at
          )
          VALUES (?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE updated_at = VALUES(updated_at),
                                  changed_at = VALUES(changed_at)
    SQL

    refute_attack query, "KEY"
    refute_attack query, "VALUES"
    refute_attack query, "ON"
    refute_attack query, "UPDATE"
    refute_attack query, "INSERT"
    refute_attack query, "INTO"
  end

  test "it flags function calls as attacks" do
    assert_attack "foobar()", "foobar()"
    assert_attack "foobar(1234567)", "foobar(1234567)"
    assert_attack "foobar       ()", "foobar       ()"
    assert_attack ".foobar()", ".foobar()"
    assert_attack "20+foobar()", "20+foobar()"
    assert_attack "20-foobar(", "20-foobar("
    assert_attack "20<foobar()", "20<foobar()"
    assert_attack "20*foobar  ()", "20*foobar  ()"
    assert_attack "!foobar()", "!foobar()"
    assert_attack "=foobar()", "=foobar()"
    assert_attack "1foobar()", "1foobar()"
    assert_attack "1foo_bar()", "1foo_bar()"
    assert_attack "1foo-bar()", "1foo-bar()"
    assert_attack "#foobar()", "#foobar()"
  end

  test "it flags attacks regardless of input casing" do
    assert_attack "SELECT id FROM users WHERE email = '' or 1=1 -- a'", "' OR 1=1 -- a"
  end

  test "it does not flag VIEW as an attack when it's a substring" do
    query = <<~SQL.chomp
      SELECT views.id AS view_id, view_settings.user_id, view_settings.settings
        FROM views
        INNER JOIN view_settings ON views.id = view_settings.view_id AND view_settings.user_id = ?
        WHERE views.business_id = ?
    SQL

    refute_attack query, "view_id"
    refute_attack query, "view_settings"

    refute_attack <<~SQL.chomp, "view"
      SELECT id,
             business_id,
             object_type,
             name,
             `condition`,
             settings,
             `read_only`,
             created_at,
             updated_at
      FROM views
      WHERE business_id = ?
    SQL
  end

  test "ignores purely alphanumeric input" do
    refute_attack "SELECT * FROM users123", "users123"
    refute_attack "SELECT * FROM users_123", "users_123"
  end

  test "ignores input that does not show up in the SQL query" do
    refute_attack "SELECT * FROM users WHERE id IN (1,2,3)", "1,2,3"
    refute_attack "SELECT * FROM users", "1,2,3"
  end

  test "attacks are not prevented if libzen can't be loaded" do
    assert_attack "SELECT * FROM users WHERE id = '' OR true; --'", "' OR true; --'"

    fail_to_load_error = ->(query, *) {
      err = format("%p for SQL injection", query)
      raise Aikido::Zen::InternalsError.new(err, "loading", "libzen.dylib")
    }

    err = assert_raise Aikido::Zen::InternalsError do
      Aikido::Zen::Internals.stub(:detect_sql_injection, fail_to_load_error) do
        refute_attack "SELECT * FROM users WHERE id = '' OR true; --'", "' OR true; --'"
      end
    end

    assert_equal %(Zen could not scan "select * from users where id = '' or true; --'" for SQL injection due to a problem loading the library `libzen.dylib'), err.message
  end

  test "internal errors are raised as InternalError" do
    Aikido::Zen::Internals.stub(:detect_sql_injection_native, 2) do
      err = assert_raise Aikido::Zen::InternalsError do
        scan "SELECT * FROM users WHERE <something>", "<something>", :common
      end

      assert_equal %(Zen could not scan SQL query "select * from users where <something>" with input "<something>" due to a problem calling detect_sql_injection in the library `#{Aikido::Zen::Internals.libzen_name}'), err.message
    end
  end

  class TestMySQLDialect < ActiveSupport::TestCase
    include Assertions

    def assert_attack(query, input = query, *args)
      super(query, input, :mysql, *args)
    end

    def refute_attack(query, input = query, *args)
      super(query, input, :mysql, *args)
    end

    test "flags MySQL bitwise operator as SQL injection" do
      assert_attack "SELECT 10 ^ 12", "10 ^ 12"
    end

    test "ignores PostgreSQL dollar signs" do
      refute_attack "SELECT $$", "$$"
      refute_attack "SELECT $$text$$", "$$text$$"
      refute_attack "SELECT $tag$text$tag$", "$tag$text$tag$"
    end

    test "flags SET GLOBAL as an attack" do
      assert_attack "SET GLOBAL max_connections = 1000", "GLOBAL max_connections"
      assert_attack "SET @@GLOBAL.max_connections = 1000", "@@GLOBAL.max_connections = 1000"
      assert_attack "SET @@GLOBAL.max_connections=1000", "@@GLOBAL.max_connections=1000"

      refute_attack "SELECT * FROM users WHERE id = 'SET GLOBAL max_connections = 1000'", "SET GLOBAL max_connections = 1000"
      refute_attack "SELECT * FROM users WHERE id = 'SET @@GLOBAL.max_connections = 1000'", "SET @@GLOBAL.max_connections = 1000"
    end

    test "flags SET SESSION as an attack" do
      assert_attack "SET SESSION max_connections = 1000", "SESSION max_connections"
      assert_attack "SET @@SESSION.max_connections = 1000", "@@SESSION.max_connections = 1000"
      assert_attack "SET @@SESSION.max_connections=1000", "@@SESSION.max_connections=1000"

      refute_attack "SELECT * FROM users WHERE id = 'SET SESSION max_connections = 1000'", "SET SESSION max_connections = 1000"
      refute_attack "SELECT * FROM users WHERE id = 'SET @@SESSION.max_connections = 1000'", "SET @@SESSION.max_connections = 1000"
    end

    test "flags SET CHARACTER SET as an attack" do
      assert_attack "SET CHARACTER SET utf8", "CHARACTER SET utf8"
      assert_attack "SET CHARACTER SET=utf8", "CHARACTER SET=utf8"
      assert_attack "SET CHARSET utf8", "CHARSET utf8"
      assert_attack "SET CHARSET=utf8", "CHARSET=utf8"

      refute_attack "SELECT * FROM users WHERE id = 'SET CHARACTER SET utf8'", "SET CHARACTER SET utf8"
      refute_attack "SELECT * FROM users WHERE id = 'SET CHARACTER SET=utf8'", "SET CHARACTER SET=utf8"
      refute_attack "SELECT * FROM users WHERE id = 'SET CHARSET utf8'", "SET CHARSET utf8"
      refute_attack "SELECT * FROM users WHERE id = 'SET CHARSET=utf8'", "SET CHARSET=utf8"
    end
  end

  class TestPostgreSQLDialect < ActiveSupport::TestCase
    include Assertions

    def assert_attack(query, input = query, *args)
      super(query, input, :postgresql, *args)
    end

    def refute_attack(query, input = query, *args)
      super(query, input, :postgresql, *args)
    end

    test "flags postgres bitwise operator as SQL injection" do
      assert_attack "SELECT 10 # 12", "10 # 12"
    end

    test "flags postgres type cast operator as SQL injection" do
      assert_attack "SELECT abc::date", "abc::date"
    end

    test "flags CLIENT_ENCODING as SQL injection" do
      assert_attack "SET CLIENT_ENCODING TO 'UTF8'", "CLIENT_ENCODING TO 'UTF8'"
      assert_attack "SET CLIENT_ENCODING = 'UTF8'", "CLIENT_ENCODING = 'UTF8'"
      assert_attack "SET CLIENT_ENCODING='UTF8'", "CLIENT_ENCODING='UTF8'"

      refute_attack %(SELECT * FROM users WHERE id = 'SET CLIENT_ENCODING = "UTF8"'), 'SET CLIENT_ENCODING = "UTF8"'
      refute_attack %(SELECT * FROM users WHERE id = 'SET CLIENT_ENCODING TO "UTF8"'), 'SET CLIENT_ENCODING TO "UTF8"'
    end
  end

  class TestSQLiteDialect < ActiveSupport::TestCase
    include Assertions

    def assert_attack(query, input = query, *args)
      super(query, input, :sqlite, *args)
    end

    def refute_attack(query, input = query, *args)
      super(query, input, :sqlite, *args)
    end

    test "flags the VACUUM command as SQL injection" do
      assert_attack "VACUUM;", "VACUUM;"
    end

    test "does not flag the VACUUM command without semicolon as SQL injection" do
      refute_attack "VACUUM;", "VACUUM"
    end

    test "flags the ATTACH command as SQL injection" do
      assert_attack "ATTACH DATABASE 'test.db' AS test;", "'test.db' AS test"
    end

    test "ignores postgres dollar signs" do
      refute_attack "SELECT $$", "$$"
      refute_attack "SELECT $$text$$", "$$text$$"
      refute_attack "SELECT $tag$text$tag$", "$tag$text$tag$"
    end
  end
end
