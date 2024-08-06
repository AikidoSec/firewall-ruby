# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::Vulnerabilities::SQLInjectionScannerTest < Minitest::Test
  module Assertions
    def assert_attack(query, input = query, dialect = :common, reason = "`#{input}` was not blocked (#{dialect})")
      scanner = Aikido::Firewall::Vulnerabilities::SQLInjectionScanner.new(query, input, dialect)
      assert scanner.attack?, reason
    end

    def refute_attack(query, input = query, dialect = :common, reason = "`#{input}` was blocked (#{dialect})")
      scanner = Aikido::Firewall::Vulnerabilities::SQLInjectionScanner.new(query, input, dialect)
      refute scanner.attack?, reason
    end
  end

  include Assertions

  def assert_attack(query, input = query, *args)
    super(query, input, :mysql, *args)
    super(query, input, :postgresql, *args)
  end

  def refute_attack(query, input = query, *args)
    super(query, input, :mysql, *args)
    super(query, input, :postgresql, *args)
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
    assert_attack "I'm writting you"
    assert_attack "Termin;ate"
    assert_attack "Roses <> violets"
    assert_attack "Roses < Violets"
    assert_attack "Roses > Violets"
    assert_attack "Roses != Violets"

    assert_attack "UNTER;"
  end

  test "rejects input trying to escape the quote characters" do
    assert_attack "SELECT * FROM users WHERE id = 'users\\'", "users\\"
    assert_attack "SELECT * FROM users WHERE id = 'users\\\\'", "users\\\\"
  end

  test "allows input with allowed escape sequences" do
    refute_attack "SELECT * FROM users WHERE id = '\nusers'", "\nusers"
    refute_attack "SELECT * FROM users WHERE id = '\rusers'", "\rusers"
    refute_attack "SELECT * FROM users WHERE id = '\tusers'", "\tusers"
  end

  test "rejects input that includes unescaped quotes" do
    assert_attack %(SELECT * FROM comments WHERE comment = 'I'm writting you'), "I'm writting you"
    assert_attack %(SELECT * FROM comments WHERE comment = "I"m writting you"), 'I"m writting you'
    assert_attack "SELECT * FROM `comm`ents`", "`comm`ents"
  end

  # rubocop:disable Style/StringLiterals
  test "allows input with escaped quotes" do
    refute_attack %(SELECT * FROM comments WHERE comment = "I'm writting you"), "I'm writting you"
    refute_attack %(SELECT * FROM comments WHERE comment = "I`m writting you"), "I`m writting you"
    refute_attack %(SELECT * FROM comments WHERE comment = "I\\"m writting you"), "I\"m writting you"
    refute_attack %(SELECT * FROM comments WHERE comment = 'I"m writting you'), 'I"m writting you'
    refute_attack %(SELECT * FROM comments WHERE comment = 'I`m writting you'), 'I"m writting you'
    refute_attack %(SELECT * FROM comments WHERE comment = 'I\\'m writting you'), 'I\'m writting you'
    refute_attack %(SELECT * FROM comments WHERE comment = `I"m writting you`), 'I"m writting you'
    refute_attack %(SELECT * FROM comments WHERE comment = `I'm writting you`), "I'm writting you"
    refute_attack %(SELECT * FROM comments WHERE comment = `I\\`m writting you`), "I`m writting you"
    refute_attack "SELECT * FROM `comm'ents`", "comm'ents"
  end
  # rubocop:enable Style/StringLiterals

  test "allows quoted comments" do
    refute_attack "SELECT * FROM hashtags WHERE name = '#hashtag'", "#hashtag"
    refute_attack "SELECT * FROM hashtags WHERE name = '-- nope'", "-- nope"
  end

  test "allows input inside a comment" do
    refute_attack "SELECT * FROM hashtags WHERE name = 'name' -- Query by name", "name"
  end

  test "allows comments at the end of the query" do
    skip <<~REASON
      Although this is valid and not dangerous, our algorithm isn't good enough
      to treat this properly yet. We can consider it an edge case, since users
      really shouldn't be adding comments to your SQL queries.
    REASON

    refute_attack "SELECT * FROM hashtags WHERE id = 1 -- Query by name", "-- Query by name"
  end

  test "allows words that include SQL keywords but have extra characters" do
    refute_attack "Roses are red rollbacks are blue"
    refute_attack "Roses are red truncates are blue"
    refute_attack "Roses are reddelete are blue"
    refute_attack "Roses are red WHEREis blue"
    refute_attack "Roses are red ORis isAND"
  end

  test "allows SQL functions that should not be blocked" do
    refute_attack "I was benchmark ing"
    refute_attack "We were delay ed"
    refute_attack "I will waitfor you"
  end

  test "allows some special characters and single character queries" do
    refute_attack "steve@yahoo.com"
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

  test "handles user input inside IN (...) statements" do
    assert_attack "SELECT * FROM users WHERE id IN ('123')", "'123'"
    refute_attack "SELECT * FROM users WHERE id IN (123)", "123"
    refute_attack "SELECT * FROM users WHERE id IN (123, 456)", "123"
    refute_attack "SELECT * FROM users WHERE id IN (123, 456)", "456"
    refute_attack "SELECT * FROM users WHERE id IN ('123')", "123"
    refute_attack "SELECT * FROM users WHERE id IN (13,14,15)", "13,14,15"
    refute_attack "SELECT * FROM users WHERE id IN (13, 14, 154)", "13, 14, 154"

    assert_attack "SELECT * FROM users WHERE id IN (13, 14, 154) OR (1=1)", "13, 14, 154) OR (1=1"
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
    assert_attack <<~QUERY.chomp, "users`"
      SELECT * FROM `users``
      WHERE id = 123
    QUERY

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

  test "it flags dangerous strings as attacks" do
    Aikido::Firewall::Vulnerabilities::SQLInjection[:common].dangerous_syntax.each do |token|
      input = "#{token} a" # needs to be longer than one character
      assert_attack "SELECT * FROM users WHERE #{input}", input
    end
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

    refute_attack "foobar)", "foobar)"
    refute_attack "foobar      )", "foobar      )"
    refute_attack "€foobar()", "€foobar()"
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
    refute_attack query, "view_settings.user_id"

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

  test "it does not flag keywords by themselves as they don't pose any risk" do
    Aikido::Firewall::Vulnerabilities::SQLInjection[:common].keywords.each do |keyword|
      refute_attack "SELECT id FROM #{keyword}", keyword
      refute_attack "SELECT id FROM #{keyword}", keyword.downcase
    end
  end

  test "it flags keywords when the input contains other characters" do
    Aikido::Firewall::Vulnerabilities::SQLInjection[:common].keywords.each do |keyword|
      assert_attack "SELECT id FROM #{keyword}", " #{keyword}"
      assert_attack "SELECT id FROM #{keyword}", " #{keyword.downcase}"

      Aikido::Firewall::Vulnerabilities::SQLInjection[:common].dangerous_syntax.each do |token|
        payload = "#{keyword}#{token}"
        assert_attack "SELECT id FROM #{payload}", payload
        assert_attack "SELECT id FROM #{payload}", payload.downcase
      end
    end
  end

  test "flags common auth bypasses as attacks" do
    file_fixture("sql_injection/Auth_Bypass.txt").each_line do |payload|
      assert_attack payload.chomp
    end
  end

  class TestMySQLDialect < Minitest::Test
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

  class TestPostgreSQLDialect < Minitest::Test
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

    test "flags double dollar sign as SQL injection" do
      assert_attack "SELECT $$", "$$"
      assert_attack "SELECT $$text$$", "$$text$$"
      assert_attack "SELECT $tag$text$tag$", "$tag$text$tag$"

      refute_attack "SELECT '$$text$$'", "$$text$$"
    end

    test "flags CLIENT_ENCODING as SQL injection" do
      assert_attack "SET CLIENT_ENCODING TO 'UTF8'", "CLIENT_ENCODING TO 'UTF8'"
      assert_attack "SET CLIENT_ENCODING = 'UTF8'", "CLIENT_ENCODING = 'UTF8'"
      assert_attack "SET CLIENT_ENCODING='UTF8'", "CLIENT_ENCODING='UTF8'"

      refute_attack %(SELECT * FROM users WHERE id = 'SET CLIENT_ENCODING = "UTF8"'), 'SET CLIENT_ENCODING = "UTF8"'
      refute_attack %(SELECT * FROM users WHERE id = 'SET CLIENT_ENCODING TO "UTF8"'), 'SET CLIENT_ENCODING TO "UTF8"'
    end
  end

  class TestEncapsulation < Minitest::Test
    def assert_encapsulated(query, input, reason = "`#{input}` not correctly encapsulated in `#{query}`")
      scanner = Aikido::Firewall::Vulnerabilities::SQLInjectionScanner.new(query, input, :mysql)
      assert scanner.input_quoted_or_escaped_within_query?, reason
    end

    def refute_encapsulated(query, input, reason = "`#{input}` correctly encapsulated in `#{query}`")
      scanner = Aikido::Firewall::Vulnerabilities::SQLInjectionScanner.new(query, input, :mysql)
      refute scanner.input_quoted_or_escaped_within_query?, reason
    end

    test "input is correctly quoted inside query" do
      assert_encapsulated %( Hello Hello 'UNION' and also "UNION" ), "UNION"
      assert_encapsulated %("UNION"), "UNION"
      assert_encapsulated %(`UNION`), "UNION"
      assert_encapsulated %( 'UNION' ), "UNION"

      refute_encapsulated %(UNION), "UNION"
    end

    test "all instances of input should be quoted inside query" do
      assert_encapsulated %("UNION"'UNION'), "UNION"
      refute_encapsulated %(UNION"UNION"'UNION'), "UNION"
      refute_encapsulated %('UNION'"UNION"UNION), "UNION"
      refute_encapsulated %('UNION'UNION"UNION"), "UNION"
    end

    test "input with quotes inside" do
      assert_encapsulated %(SELECT * FROM cats WHERE id = 'UN"ION' AND id = "UN'ION"), 'UN"ION'
      refute_encapsulated %(SELECT * FROM cats WHERE id = 'UN'ION' AND id = "UN'ION"), "UN'ION"
      refute_encapsulated %(SELECT * FROM cats WHERE id = 'UN`ION' AND id = `UN`ION`), "UN`ION"
    end

    test "input escaping the closing quote" do
      refute_encapsulated %(SELECT * FROM cats WHERE id = 'UNION\\'), "UNION\\"
      refute_encapsulated %(SELECT * FROM cats WHERE id = 'UNION\\\\'), "UNION\\\\"
      refute_encapsulated %(SELECT * FROM cats WHERE id = 'UNION\\\\\\'), "UNION\\\\\\"
    end

    test "input with unbalanced quotes" do
      refute_encapsulated %(SELECT * FROM users WHERE id = '\\'hello'), "'hello'"
      refute_encapsulated %(SELECT * FROM users WHERE id = "\\"hello"), '"hello"'
    end

    test "input surrounded with balanced quotes" do
      assert_encapsulated %(SELECT * FROM users WHERE id = '\\'hello\\''), "'hello'"
      assert_encapsulated %(SELECT * FROM users WHERE id = "\\"hello\\""), '"hello"'
      assert_encapsulated %(SELECT * FROM users WHERE id = `\\`hello\\``), "`hello`"
    end

    test "input starts with a stray quote" do
      assert_encapsulated %(SELECT * FROM users WHERE id = '\\' or true--'), "' or true--"
      assert_encapsulated %(SELECT * FROM users WHERE id = "\\" or true--"), '" or true--'
      assert_encapsulated %(SELECT * FROM users WHERE id = `\\` or true--`), "` or true--"

      assert_encapsulated %(SELECT * FROM users WHERE id = '\\' hello world'), "' hello world"
      assert_encapsulated %(SELECT * FROM users WHERE id = "\\" hello world"), '" hello world'
      assert_encapsulated %(SELECT * FROM users WHERE id = `\\` hello world`), "` hello world"
    end

    test "input starts with stray quote and appears multiple times in query" do
      assert_encapsulated %(SELECT * FROM users WHERE id = '\\'hello' AND id = '\\'hello'), "'hello"
      assert_encapsulated %(SELECT * FROM users WHERE id = "\\"hello" AND id = "\\"hello"), '"hello'
      assert_encapsulated %(SELECT * FROM users WHERE id = `\\`hello` AND id = `\\`hello`), "`hello"

      refute_encapsulated %(SELECT * FROM users WHERE id = '\\'hello' AND id = 'hello'), "'hello"
      refute_encapsulated %(SELECT * FROM users WHERE id = "\\"hello" AND id = "hello"), '"hello'
      refute_encapsulated %(SELECT * FROM users WHERE id = `\\`hello` AND id = `hello`), "`hello"
    end

    test "input with allowed escape sequences" do
      assert_encapsulated %(SELECT * FROM cats WHERE id = 'UNION\\n'), "UNION\\n"
      assert_encapsulated %(SELECT * FROM cats WHERE id = '\\tUNION\\t'), "\\tUNION\\t"
      assert_encapsulated %(SELECT * FROM cats WHERE id = '\\rUNION'), "\\rUNION"
    end

    test "using single quotes as an escape sequence for single quotes" do
      skip <<~REASON
        The current algorithm is not very clever, and doesn't quite support
        escaping strings this way. However, since this is not the most used
        syntax, we're OK with not supporting it for the time being.
      REASON

      assert_encapsulated %(SELECT * FROM users WHERE id = '''&'''), "'&'"
    end
  end
end
