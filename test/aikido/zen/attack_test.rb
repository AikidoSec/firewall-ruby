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

    test "generates the proper exception" do
      attack = Aikido::Zen::Attacks::SQLInjectionAttack.new(
        query: @query, input: @input, dialect: @dialect, sink: @sink, context: @context, operation: @op
      )

      assert_kind_of Aikido::Zen::SQLInjectionError, attack.exception
      assert_equal @query, attack.exception.query
      assert_equal @input, attack.exception.input
      assert_equal @dialect, attack.exception.dialect
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
        metadata: {
          sql: @query,
          dialect: @dialect.name
        },
        source: "routeParams",
        path: "id"
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
        metadata: {
          sql: @query,
          dialect: @dialect.name
        },
        source: "routeParams",
        path: "id"
      }

      assert_equal expected, attack.as_json
    end
  end

  class SSRFAttackTest < ActiveSupport::TestCase
    setup do
      @request_uri = URI("http://localhost:7000/api/users")
      @request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
        verb: "GET",
        uri: @request_uri,
        headers: {}
      )
      @input = Aikido::Zen::Payload.new("localhost:7000", :body, "url")
      @context = Aikido::Zen::Context.from_rack_env({})
      @op = "net-http.request"
      @sink = Sink.new("net-http", scanners: [NOOP])
    end

    test "keeps track of the request and triggering input" do
      attack = Aikido::Zen::Attacks::SSRFAttack.new(
        request: @request, input: @input, sink: @sink, context: @context, operation: @op
      )

      assert_equal @request, attack.request
      assert_equal @input, attack.input
      assert_equal @sink, attack.sink
      assert_equal @context, attack.context
      assert_equal @op, attack.operation
    end

    test "generates the proper exception" do
      attack = Aikido::Zen::Attacks::SSRFAttack.new(
        request: @request, input: @input, sink: @sink, context: @context, operation: @op
      )

      assert_kind_of Aikido::Zen::SSRFDetectedError, attack.exception
    end

    test "can track if the Agent will block it" do
      attack = Aikido::Zen::Attacks::SSRFAttack.new(
        request: @request, input: @input, sink: @sink, context: @context, operation: @op
      )

      refute attack.blocked?

      attack.will_be_blocked!
      assert attack.blocked?
    end

    test "#metadata includes hostname and port as strings" do
      attack = Aikido::Zen::Attacks::SSRFAttack.new(
        request: @request, input: @input, sink: @sink, context: @context, operation: @op
      )

      metadata = attack.metadata

      assert_equal "localhost", metadata[:hostname]
      assert_equal "7000", metadata[:port]
      assert_kind_of String, metadata[:port], "Port should be a string, not an integer"
    end

    test "#as_json includes the expected fields with port as string" do
      attack = Aikido::Zen::Attacks::SSRFAttack.new(
        request: @request, input: @input, sink: @sink, context: @context, operation: @op
      )

      expected = {
        kind: "ssrf",
        operation: @op,
        blocked: false,
        payload: @input.value,
        metadata: {
          hostname: "localhost",
          port: "7000"
        },
        source: "body",
        path: "url"
      }

      assert_equal expected, attack.as_json
    end

    test "#as_json reflects if the attack was blocked" do
      attack = Aikido::Zen::Attacks::SSRFAttack.new(
        request: @request, input: @input, sink: @sink, context: @context, operation: @op
      )

      attack.will_be_blocked!

      expected = {
        kind: "ssrf",
        operation: @op,
        blocked: true,
        payload: @input.value,
        metadata: {
          hostname: "localhost",
          port: "7000"
        },
        source: "body",
        path: "url"
      }

      assert_equal expected, attack.as_json
    end

    test "#metadata handles default HTTP port 80" do
      http_uri = URI("http://example.com/path")
      request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
        verb: "GET",
        uri: http_uri,
        headers: {}
      )
      attack = Aikido::Zen::Attacks::SSRFAttack.new(
        request: request, input: @input, sink: @sink, context: @context, operation: @op
      )

      metadata = attack.metadata

      assert_equal "example.com", metadata[:hostname]
      assert_equal "80", metadata[:port]
      assert_kind_of String, metadata[:port]
    end

    test "#metadata handles default HTTPS port 443" do
      https_uri = URI("https://example.com/path")
      request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
        verb: "GET",
        uri: https_uri,
        headers: {}
      )
      attack = Aikido::Zen::Attacks::SSRFAttack.new(
        request: request, input: @input, sink: @sink, context: @context, operation: @op
      )

      metadata = attack.metadata

      assert_equal "example.com", metadata[:hostname]
      assert_equal "443", metadata[:port]
      assert_kind_of String, metadata[:port]
    end
  end
end
