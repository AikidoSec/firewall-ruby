# frozen_string_literal: true

require_relative "sinks/mysql2" if defined?(::Mysql2)
require_relative "sinks/pg" if defined?(::PG)
require_relative "sinks/trilogy" if defined?(::Trilogy)
