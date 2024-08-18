# frozen_string_literal: true

require "test_helper"

module Aikido::Firewall
  class SQLInjectionTest < ActiveSupport::TestCase
    setup do
      @query = "SELECT * FROM users WHERE id = '' OR 1=1 --'"
      @input = "' OR 1=1 --"
      @dialect = Aikido::Firewall::Vulnerabilities::SQLInjection[:common]
      @request = Aikido::Agent::Request.new({})
      @op = "test.op"
      @sink = Sink.new("test", scanners: [NOOP])
    end

    test "keeps track of the query and triggering input" do
      attack = Aikido::Firewall::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, request: @request, operation: @op
      )

      assert_equal @query, attack.query
      assert_equal @input, attack.input
      assert_equal @dialect, attack.dialect
      assert_equal @sink, attack.sink
      assert_equal @request, attack.request
      assert_equal @op, attack.operation
    end

    test "generates a useful log message from the data" do
      attack = Aikido::Firewall::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, request: @request, operation: @op
      )

      assert_equal <<~TXT.chomp, attack.log_message
        SQL Injection: Malicious user input «' OR 1=1 --» detected in SQL query «SELECT * FROM users WHERE id = '' OR 1=1 --'»
      TXT
    end

    test "correclty identifies the MySQL dialect in the log message" do
      dialect = Aikido::Firewall::Vulnerabilities::SQLInjection[:mysql]
      attack = Aikido::Firewall::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: dialect, sink: @sink, request: @request, operation: @op
      )

      assert_match(/in MySQL query/, attack.log_message)
    end

    test "correclty identifies the PostgreSQL dialect in the log message" do
      dialect = Aikido::Firewall::Vulnerabilities::SQLInjection[:postgresql]
      attack = Aikido::Firewall::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: dialect, sink: @sink, request: @request, operation: @op
      )

      assert_match(/in PostgreSQL query/, attack.log_message)
    end

    test "correclty identifies the SQLite dialect in the log message" do
      dialect = Aikido::Firewall::Vulnerabilities::SQLInjection[:sqlite]
      attack = Aikido::Firewall::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: dialect, sink: @sink, request: @request, operation: @op
      )

      assert_match(/in SQLite query/, attack.log_message)
    end

    test "generates the proper exception" do
      attack = Aikido::Firewall::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, request: @request, operation: @op
      )

      assert_kind_of Aikido::Firewall::SQLInjectionError, attack.exception
      assert_equal @query, attack.exception.query
      assert_equal @input, attack.exception.input
      assert_equal @dialect, attack.exception.dialect
      assert_equal attack.log_message, attack.exception.message
    end

    test "can track if the Agent will block it" do
      attack = Aikido::Firewall::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, request: @request, operation: @op
      )

      refute attack.blocked?

      attack.will_be_blocked!
      assert attack.blocked?
    end

    test "#as_json includes the expected fields" do
      attack = Aikido::Firewall::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, request: @request, operation: @op
      )

      # debugger
    end
  end
end
