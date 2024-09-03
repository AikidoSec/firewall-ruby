# frozen_string_literal: true

require_relative "sink"

require_relative "sinks/net_http" if defined?(::Net::HTTP)
require_relative "sinks/http" if defined?(::HTTP)
require_relative "sinks/httpx" if defined?(::HTTPX)
require_relative "sinks/httpclient" if defined?(::HTTPClient)
require_relative "sinks/excon" if defined?(::Excon)
require_relative "sinks/mysql2" if defined?(::Mysql2)
require_relative "sinks/pg" if defined?(::PG)
require_relative "sinks/sqlite3" if defined?(::SQLite3)
require_relative "sinks/trilogy" if defined?(::Trilogy)
