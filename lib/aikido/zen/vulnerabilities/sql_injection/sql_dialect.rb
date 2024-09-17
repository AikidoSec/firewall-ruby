# frozen_string_literal: true

module Aikido::Zen::Vulnerabilities
  module SQLInjection
    # Fetches a dialect implementation by key.
    #
    # @param dialect [Symbol] one of `:mysql`, `:postgresql`, `:sqlite`.
    #
    # @raise [KeyError] if given an invalid dialect key.
    # @return [SQLDialect]
    def self.[](dialect)
      @dialects.fetch(dialect)
    end

    # Implements dialect-specific things like special syntax or keywords. This
    # can be used to check if a String contains embedded SQL.
    #
    # @api private
    class SQLDialect
      attr_reader :name

      # @return [Array<String>] the corresponding (keywords, operators, etc)
      #   tokens for this dialect.
      attr_reader :keywords, :operators, :dangerous_syntax

      def initialize(name:, keywords: [], operators: [], dangerous_syntax: [])
        @name = name
        @keywords = KEYWORDS + escape(keywords)
        @operators = OPERATORS + escape(operators)
        @dangerous_syntax = DANGEROUS_SYNTAX + escape(dangerous_syntax)
      end

      def match?(input)
        syntax_regexp.match?(input)
      end
      alias_method :===, :match?

      def to_s
        name.to_s
      end

      private def syntax_regexp
        return @syntax_regexp if defined?(@syntax_regexp)

        # Match keywords that are neither preceeded nor followed by any letters
        # or underscores
        match_keywords = "(?<![a-z_])(#{@keywords.join("|")})(?![a-z_])"

        match_operators = "(#{@operators.join("|")})"

        match_functions = [
          "(?<=#{["\\s", "\\.", "^", *@operators].join("|")})",
          "([a-z0-9_-]+)",
          "(?=[\\s]*\\()"
        ].join

        match_dangerous_syntax = @dangerous_syntax.join("|")

        @syntax_regexp = Regexp.new(
          [match_keywords, match_operators, match_functions, match_dangerous_syntax].join("|"),
          "im"
        )
      end

      private def escape(list)
        list.map { |el| Regexp.escape(el) }
      end

      KEYWORDS = %w[
        INSERT SELECT CREATE DROP DATABASE UPDATE DELETE ALTER GRANT SAVEPOINT
        COMMIT ROLLBACK TRUNCATE OR AND UNION AS WHERE DISTINCT FROM INTO TOP
        BETWEEN LIKE IN NULL NOT TABLE INDEX VIEW COUNT SUM AVG MIN MAX GROUP BY
        HAVING DESC ASC OFFSET FETCH LEFT RIGHT INNER OUTER JOIN EXISTS REVOKE
        ALL LIMIT ORDER ADD CONSTRAINT COLUMN ANY BACKUP CASE CHECK REPLACE
        DEFAULT EXEC FOREIGN KEY FULL PROCEDURE ROWNUM SET SESSION GLOBAL UNIQUE
        VALUES COLLATE IS
      ].map { |keyword| Regexp.escape(keyword) }

      OPERATORS = %w[= ! ; + - * / % & | ^ > < # ::].map { |op| Regexp.escape(op) }

      # Characters or sequences that are dangerous inside a string and can be
      # abused.
      DANGEROUS_SYNTAX = %w[" ' ` \\ /* */ -- #].map { |syn| Regexp.escape(syn) }
    end

    @dialects = {
      common: SQLDialect.new(name: "SQL"),

      mysql: SQLDialect.new(
        name: "MySQL",
        keywords: [
          # https://dev.mysql.com/doc/refman/8.0/en/set-variable.html
          "GLOBAL",
          "SESSION",
          "PERSIST",
          "PERSIST_ONLY",
          "@@GLOBAL",
          "@@SESSION",

          # https://dev.mysql.com/doc/refman/8.0/en/set-character-set.html
          "CHARACTER SET",
          "CHARSET"
        ]
      ),

      postgresql: SQLDialect.new(
        name: "PostgreSQL",
        keywords: [
          # https://www.postgresql.org/docs/current/sql-set.html
          "CLIENT_ENCODING"
        ],
        dangerous_syntax: [
          # https://www.postgresql.org/docs/current/sql-syntax-lexical.html#SQL-SYNTAX-DOLLAR-QUOTING
          "$"
        ]
      ),

      sqlite: SQLDialect.new(
        name: "SQLite",
        keywords: ["VACUUM", "ATTACH", "DETACH"]
      )
    }
  end
end
