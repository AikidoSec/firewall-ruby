# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::TrilogyTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  setup do
    @db = Trilogy.new(
      host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
      port: ENV.fetch("MYSQL_PORT", "3306"),
      username: ENV.fetch("MYSQL_USERNAME", "root"),
      password: ENV.fetch("MYSQL_PASSWORD", "")
    )

    @sink = Aikido::Zen::Sinks::Trilogy::SINK
  end

  test "scans queries via #query" do
    mock = Minitest::Mock.new
    mock.expect :call, nil,
      query: String,
      dialect: :mysql,
      scan: Aikido::Zen::Scan,
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
    set_context_from_request_to "/?q=1'%20OR%20''='';--%20"

    assert_attack Aikido::Zen::Attacks::SQLInjectionAttack do
      @db.query "SELECT 1 WHERE 1 = '1' OR ''='';-- '"
    end
  end

  test "doesn't fail when the user input is properly escaped" do
    set_context_from_request_to "/?q=1'%20OR%20''='';--"

    refute_attack do
      @db.query "SELECT 1 WHERE 1 = '1'' OR ''''='''';--'"
    end
  end

  # Tests that the hardened Trilogy#escape and Trilogy#query methods prevent SQL
  # injection through strings in multibyte encodings in versions before 2.13.2:
  # https://github.com/trilogy-libraries/trilogy/security/advisories/GHSA-744p-w4gc-m3gh
  class EncodingTest < ActiveSupport::TestCase
    # A lead byte for each encoding in the advisory that forms a valid character
    # when followed by \x5C (ASCII backslash).
    ENCODING_LEAD_CHARACTERS = [
      ["Shift_JIS", "\x95"],
      ["Windows-31J", "\x95"],
      ["GBK", "\x95"],
      ["Big5", "\xA5"],
      ["GB18030", "\x95"]
    ].freeze

    setup do
      skip "Trilogy #{Trilogy::VERSION} is not vulnerable" unless Aikido::Zen.satisfy("trilogy", "< 2.13.2")

      @db = Trilogy.new(
        host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
        port: ENV.fetch("MYSQL_PORT", "3306"),
        username: ENV.fetch("MYSQL_USERNAME", "root"),
        password: ENV.fetch("MYSQL_PASSWORD", "")
      )
    end

    ENCODING_LEAD_CHARACTERS.each do |encoding, lead|
      test "#escape raises when a #{encoding} character contains a backslash byte" do
        input = (+"#{lead}\x5C' OR 1=1-- ").force_encoding(encoding)

        err = assert_raises(Encoding::CompatibilityError) { @db.escape(input) }
        assert_match(/Zen prevented a #{encoding} string that cannot be safely escaped/, err.message)
      end

      test "#escape raises when a #{encoding} string is invalid" do
        input = (+"#{lead}' OR 1=1-- ").force_encoding(encoding)

        assert_raises(Encoding::CompatibilityError) { @db.escape(input) }
      end

      test "#query raises when a #{encoding} character contains a backslash byte" do
        sql = (+"SELECT '#{lead}\x5C' AS r").force_encoding(encoding)

        assert_raises(Encoding::CompatibilityError) { @db.query(sql) }
      end

      test "#query raises when a #{encoding} string is invalid" do
        sql = (+"SELECT '#{lead}' AS r").force_encoding(encoding)

        assert_raises(Encoding::CompatibilityError) { @db.query(sql) }
      end
    end

    test "#escape allows strings that are safe to escape" do
      assert_equal "it\\'s", @db.escape("it's")
      assert_equal "é\\'", @db.escape("é'")
      assert_equal "\xFF\\'".b, @db.escape("\xFF'".b)
      assert_equal "it\\'s".encode("Shift_JIS"), @db.escape("it's".encode("Shift_JIS"))
      assert_equal "é\\'".encode("ISO-8859-1"), @db.escape("é'".encode("ISO-8859-1"))
      assert_equal "ア\\'".encode("Shift_JIS"), @db.escape("ア'".encode("Shift_JIS"))
    end

    test "#query allows strings that are safe to query" do
      assert_equal [[1]], @db.query("SELECT 1".encode("Shift_JIS")).to_a
      assert_equal [["表"]], @db.query("SELECT '表'".b).to_a
      assert_equal [["表"]], @db.query("SELECT '表'").to_a
    end

    test "#escape raises when the argument is not a string" do
      err = assert_raises(TypeError) { @db.escape(nil) }
      assert_equal "no implicit conversion of NilClass into String", err.message

      err = assert_raises(TypeError) { @db.escape(1) }
      assert_equal "no implicit conversion of Integer into String", err.message
    end

    test "#query raises when the argument is not a string" do
      err = assert_raises(TypeError) { @db.query(nil) }
      assert_equal "no implicit conversion of NilClass into String", err.message

      err = assert_raises(TypeError) { @db.query(1) }
      assert_equal "no implicit conversion of Integer into String", err.message
    end

    test "#escape accepts an object that responds to to_str" do
      assert_equal "it\\'s", @db.escape(Struct.new(:to_str).new("it's"))
    end

    test "#query accepts an object that responds to to_str" do
      assert_equal [[1]], @db.query(Struct.new(:to_str).new("SELECT 1")).to_a
    end

    test "#escape raises when to_str returns an unsafe string" do
      unsafe = (+"\x95\x5C").force_encoding("Shift_JIS")

      assert_raises(Encoding::CompatibilityError) { @db.escape(Struct.new(:to_str).new(unsafe)) }
    end

    test "#query raises when to_str returns an unsafe string" do
      unsafe = (+"SELECT '\x95\x5C'").force_encoding("Shift_JIS")

      assert_raises(Encoding::CompatibilityError) { @db.query(Struct.new(:to_str).new(unsafe)) }
    end

    test "#escape is unchanged when hardened mode is disabled" do
      Aikido::Zen.config.harden = false

      escaped = @db.escape((+"\x95' OR 1=1-- ").force_encoding("Shift_JIS"))

      assert_equal Encoding::Shift_JIS, escaped.encoding
      assert_equal (+"\x95\\' OR 1=1-- ").force_encoding("Shift_JIS"), escaped
    end

    test "#query is unchanged when hardened mode is disabled" do
      Aikido::Zen.config.harden = false

      sql = (+"SELECT 1 /* \x95\x5c */").force_encoding("Shift_JIS")

      assert_equal [[1]], @db.query(sql).to_a
    end

    ENCODING_LEAD_CHARACTERS.each do |encoding, lead|
      test "prevents SQL injection when input tagged as #{encoding} has a character containing a backslash byte" do
        input = (+"#{lead}\x5C' OR 1=1-- ").force_encoding(encoding)

        assert_raises(Encoding::CompatibilityError) do
          @db.query "SELECT 'INJECTED' AS r WHERE 'x' = '#{@db.escape(input)}'"
        end
      end

      test "prevents SQL injection when input tagged as #{encoding} is invalid" do
        input = (+"#{lead}' OR 1=1-- ").force_encoding(encoding)

        assert_raises(Encoding::CompatibilityError) do
          @db.query "SELECT 'INJECTED' AS r WHERE 'x' = '#{@db.escape(input)}'"
        end
      end
    end
  end

  class IDORTest < ActiveSupport::TestCase
    def with_mocked_protector(params = nil)
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
      @db = Trilogy.new(
        host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
        port: ENV.fetch("MYSQL_PORT", "3306"),
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
