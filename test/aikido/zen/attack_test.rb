# frozen_string_literal: true

require "test_helper"

module Aikido::Zen
  class SQLInjectionTest < ActiveSupport::TestCase
    setup do
      @query = "SELECT * FROM users WHERE id = '' OR 1=1 --'"
      @input = Aikido::Zen::Payload.new("' OR 1=1 --", :route, "id")
      @dialect = Aikido::Zen::Scanners::SQLInjectionScanner::DIALECTS[:common]
      @context = Aikido::Zen::Context.from_rack_env({})
      @op = "test.op"
      @sink = Sink.new("test", scanners: [NOOP])
    end

    test "keeps track of the query and triggering input" do
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, context: @context, operation: @op
      )

      assert_equal @query, attack.query
      assert_equal @input, attack.input
      assert_equal @dialect, attack.dialect
      assert_equal @sink, attack.sink
      assert_equal @context, attack.context
      assert_equal @op, attack.operation
    end

    test "generates a useful log message from the data" do
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, context: @context, operation: @op
      )

      assert_equal <<~TXT.chomp, attack.log_message
        SQL Injection: Malicious user input «' OR 1=1 --» detected in SQL query «SELECT * FROM users WHERE id = '' OR 1=1 --'»
      TXT
    end

    test "correctly identifies the MySQL dialect in the log message" do
      dialect = Aikido::Zen::Scanners::SQLInjectionScanner::DIALECTS[:mysql]
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: dialect, sink: @sink, context: @context, operation: @op
      )

      assert_match(/in MySQL query/, attack.log_message)
    end

    test "correctly identifies the PostgreSQL dialect in the log message" do
      dialect = Aikido::Zen::Scanners::SQLInjectionScanner::DIALECTS[:postgresql]
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: dialect, sink: @sink, context: @context, operation: @op
      )

      assert_match(/in PostgreSQL query/, attack.log_message)
    end

    test "correctly identifies the SQLite dialect in the log message" do
      dialect = Aikido::Zen::Scanners::SQLInjectionScanner::DIALECTS[:sqlite]
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: dialect, sink: @sink, context: @context, operation: @op
      )

      assert_match(/in SQLite query/, attack.log_message)
    end

    test "generates the proper exception" do
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, context: @context, operation: @op
      )

      assert_kind_of Aikido::Zen::SQLInjectionError, attack.exception
      assert_equal @query, attack.exception.query
      assert_equal @input, attack.exception.input
      assert_equal @dialect, attack.exception.dialect
      assert_equal attack.log_message, attack.exception.message
    end

    test "can track if the Agent will block it" do
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, context: @context, operation: @op
      )

      refute attack.blocked?

      attack.will_be_blocked!
      assert attack.blocked?
    end

    test "#as_json includes the expected fields" do
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, context: @context, operation: @op
      )

      expected = {
        kind: "sql_injection",
        operation: @op,
        blocked: false,
        payload: @input.value,
        metadata: {sql: @query},
        source: "routeParams",
        pathToPayload: "id"
      }

      assert_equal expected, attack.as_json
    end

    test "#as_json reflects if the attack was blocked" do
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, context: @context, operation: @op
      )

      attack.will_be_blocked!

      expected = {
        kind: "sql_injection",
        operation: @op,
        blocked: true,
        payload: @input.value,
        metadata: {sql: @query},
        source: "routeParams",
        pathToPayload: "id"
      }

      assert_equal expected, attack.as_json
    end
  end
end
