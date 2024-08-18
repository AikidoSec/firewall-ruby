# frozen_string_literal: true

module Aikido::Firewall
  # Attack objects gather information about a type of detected attack.
  # They can be used in a few ways, like for reporting an attack event
  # to the Aikido server, or can be raised as errors to block requests
  # if blocking_mode is on.
  class Attack
    attr_reader :request
    attr_reader :operation
    attr_accessor :sink

    def initialize(request:, sink:, operation:)
      @request = request
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
        # TODO: Actually implement this.
        {
          kind: "sql_injection",
          blocked: blocked?
        }
      end

      def exception(*)
        SQLInjectionError.new(self)
      end
    end
  end
end
