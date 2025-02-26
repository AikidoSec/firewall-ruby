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

    def humanized_name
      raise NotImplementedError, "implement in subclasses"
    end

    def kind
      raise NotImplementedError, "implement in subclasses"
    end

    def input
      raise NotImplementedError, "implement in subclasses"
    end

    def metadata
      raise NotImplementedError, "implement in subclasses"
    end

    def as_json
      {
        kind: kind,
        blocked: blocked?,
        metadata: metadata,
        operation: @operation
      }.merge(input.as_json)
    end

    def exception(*)
      raise NotImplementedError, "implement in subclasses"
    end
  end

  module Attacks
    class PathTraversalAttack < Attack
      attr_reader :input
      attr_reader :filepath

      def initialize(input:, filepath:, **opts)
        super(**opts)
        @input = input
        @filepath = filepath
      end

      def metadata
        {
          expanded_filepath: filepath
        }
      end

      def humanized_name
        "path traversal attack"
      end

      def kind
        "path_traversal"
      end

      def exception(*)
        PathTraversalError.new(self)
      end
    end

    class ShellInjectionAttack < Attack
      attr_reader :input
      attr_reader :command

      def initialize(input:, command:, **opts)
        super(**opts)
        @input = input
        @command = command
      end

      def humanized_name
        "shell injection"
      end

      def kind
        "shell_injection"
      end

      def metadata
        {
          command: @command
        }
      end

      def exception(*)
        ShellInjectionError.new(self)
      end
    end

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

      def humanized_name
        "SQL injection"
      end

      def kind
        "sql_injection"
      end

      def metadata
        {sql: @query}
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

      def humanized_name
        "server-side request forgery"
      end

      def kind
        "ssrf"
      end

      def exception(*)
        SSRFDetectedError.new(self)
      end

      def metadata
        {
          host: @request.uri.hostname,
          port: @request.uri.port
        }
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

      def humanized_name
        "server-side request forgery"
      end

      def exception(*)
        SSRFDetectedError.new(self)
      end

      def kind
        "ssrf"
      end

      def input
        Aikido::Zen::Payload::UNKNOWN_PAYLOAD
      end

      def metadata
        {}
      end
    end
  end
end
