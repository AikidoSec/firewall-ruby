# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module Trilogy
      SINK = Sinks.add("trilogy", "sql_op", scanners: [Scanners::SQLInjectionScanner])

      module Helpers
        def self.scan(query, operation)
          SINK.scan(query: query, dialect: :mysql, operation: operation)
        end

        # Scans the query for SQL injection and checks it for IDOR protection.
        def self.safe_query(sql)
          Sinks::DSL.safe do
            scan(sql, "query")
          end

          Aikido::Zen.idor_protect(sql, :mysql)
        end

        # Raises when the string is in an encoding where escaping and querying
        # cannot be done safely.
        #
        # This does not depend on the encoding of the connection, which is not
        # available in every version of Trilogy.
        #
        # ASCII, UTF-8, and binary strings are safe. A string in any other encoding
        # is unsafe when its encoding is invalid or one of its multibyte characters
        # contains a backslash byte.
        #
        # @param arg [#to_str] the string passed to Trilogy#escape or Trilogy#query
        # @return [String] the argument as a string
        # @raise [TypeError] if the argument is not a string
        # @raise [Encoding::CompatibilityError] if the string is unsafe
        def self.check_string(arg)
          str = String.try_convert(arg) or raise TypeError, "no implicit conversion of #{arg.class} into String"

          return str if str.ascii_only? || str.encoding == ::Encoding::UTF_8 || str.encoding == ::Encoding::BINARY

          if !str.valid_encoding? || str.each_char.any? { |char| char.bytesize > 1 && char.b.include?("\\") }
            raise ::Encoding::CompatibilityError, "Zen prevented a #{str.encoding} string that cannot be safely escaped in hardened method. Visit https://github.com/AikidoSec/firewall-ruby for more information."
          end

          str
        end
      end

      def self.load_sinks!
        if Aikido::Zen.satisfy "trilogy", ">= 2.0"
          require "trilogy"

          ::Trilogy.class_eval do
            extend Sinks::DSL

            # Before 2.13.2, Trilogy#escape and Trilogy#query allow SQL injection
            # through strings in multibyte encodings:
            #
            # https://github.com/trilogy-libraries/trilogy/security/advisories/GHSA-744p-w4gc-m3gh
            if Aikido::Zen.satisfy "trilogy", "< 2.13.2"
              # Create a copy of the original method for internal use only.
              #
              # IMPORTANT: The copy must be created before the method is overridden.
              alias_original_method :escape__internal_for_aikido_zen, :escape

              # IMPORTANT: THE BEHAVIOR OF THIS METHOD IS CHANGED!
              #
              # Trilogy#escape escapes byte by byte, as if the string were ASCII,
              # which can swallow an escaping backslash into a multibyte character
              # and leave a quote unescaped.
              #
              # This method now raises Encoding::CompatibilityError for a non-UTF-8
              # string with an invalid encoding or a multibyte character with a
              # backslash byte.
              def escape(arg)
                # The original method crashes unless it is given a String.
                arg = Helpers.check_string(arg) if Aikido::Zen.config.harden?

                escape__internal_for_aikido_zen(arg)
              end

              # IMPORTANT: THE BEHAVIOR OF THIS METHOD IS CHANGED!
              #
              # Trilogy#query converts the query to the encoding of the connection,
              # which can swallow an escaping backslash into a multibyte character
              # and leave a quote unescaped.
              #
              # This method now raises Encoding::CompatibilityError for a non-UTF-8
              # string with an invalid encoding or a multibyte character with a
              # backslash byte.
              presafe_sink_before :query do |sql|
                Helpers.check_string(sql) if Aikido::Zen.config.harden?

                Helpers.safe_query(sql)
              end
            else
              # Code coverage is disabled here because this is environment-specific.
              # :nocov:
              presafe_sink_before :query do |sql|
                Helpers.safe_query(sql)
              end
              # :nocov:
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Trilogy.load_sinks!
