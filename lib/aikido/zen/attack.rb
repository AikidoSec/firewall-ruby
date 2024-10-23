# frozen_string_literal: true

module Aikido::Zen
  # Attack objects gather information about a type of detected attack.
  # They can be used in a few ways, like for reporting an attack event
  # to the Aikido server, or can be raised as errors to block requests
  # if blocking_mode is on.
  class Attack
    attr_reader :context
    attr_reader :operation
    attr_accessor :sink

    def initialize(context:, sink:, operation:)
      @context = context
      @operation = operation
      @sink = sink
      @blocked = false
    end

    def will_be_blocked!
      @blocked = true
    end

    def blocked?
      @blocked
    end

    def log_message
      raise NotImplementedError, "implement in subclasses"
    end

    def as_json
      raise NotImplementedError, "implement in subclasses"
    end

    def exception(*)
      raise NotImplementedError, "implement in subclasses"
    end
  end

  module Attacks
    class SQLInjectionAttack < Attack
      attr_reader :query
      attr_reader :input
      attr_reader :dialect

      def initialize(query:, input:, dialect:, **opts)
        super(**opts)
        @query = query
        @input = input
        @dialect = dialect
      end

      def log_message
        format(
          "SQL Injection: Malicious user input «%s» detected in %s query «%s»",
          @input, @dialect, @query
        )
      end

      def as_json
        {
          kind: "sql_injection",
          blocked: blocked?,
          metadata: {sql: @query},
          operation: @operation
        }.merge(@input.as_json)
      end

      def exception(*)
        SQLInjectionError.new(self)
      end
    end

    class SSRFAttack < Attack
      attr_reader :input
      attr_reader :request

      def initialize(request:, input:, **opts)
        super(**opts)
        @input = input
        @request = request
      end

      def log_message
        format(
          "SSRF: Request to user-supplied hostname «%s» detected in %s (%s).",
          @input, @operation, @request
        ).strip
      end

      def exception(*)
        SSRFDetectedError.new(self)
      end

      def as_json
        {
          kind: "ssrf",
          metadata: {host: @request.uri.hostname, port: @request.uri.port},
          blocked: blocked?,
          operation: @operation
        }.merge(@input.as_json)
      end
    end

    # Special case of an SSRF attack where we don't have a context—we're just
    # detecting a request to a particularly sensitive address.
    class StoredSSRFAttack < Attack
      attr_reader :hostname
      attr_reader :address

      def initialize(hostname:, address:, **opts)
        super(**opts)
        @hostname = hostname
        @address = address
      end

      def log_message
        format(
          "Stored SSRF: Request to sensitive host «%s» (%s) detected from unknown source in %s",
          @hostname, @address, @operation
        )
      end

      def exception(*)
        SSRFDetectedError.new(self)
      end

      def as_json
        {
          kind: "ssrf",
          blocked: blocked?,
          operation: @operation
        }
      end
    end
  end
end
