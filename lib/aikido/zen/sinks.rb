# frozen_string_literal: true

# Code coverage is disabled in this file because it is environment-specific and
# not intended to be tested directly.
# :nocov:

require_relative "sink"
require_relative "sinks_dsl"

require_relative "sinks/action_controller" if defined?(::ActionController)

# Sadly, in ruby versions lower than 3.0, it's not possible to patch the
# Kernel module because how the `prepend` method is applied
# (https://stackoverflow.com/questions/78110397/prepend-kernel-module-function-globally#comment137713906_78112924)
require_relative "sinks/kernel" if RUBY_VERSION >= "3.0"

require_relative "sinks/file"
require_relative "sinks/socket"
require_relative "sinks/resolv"
require_relative "sinks/net_http"

# http.rb aims to support and is tested against Ruby 3.0+:
# https://github.com/httprb/http?tab=readme-ov-file#supported-ruby-versions
require_relative "sinks/http" if RUBY_VERSION >= "3.0"

require_relative "sinks/httpx"
require_relative "sinks/httpclient"
require_relative "sinks/excon"
require_relative "sinks/curb"
require_relative "sinks/patron"
require_relative "sinks/typhoeus" if defined?(::Typhoeus)
require_relative "sinks/async_http"
require_relative "sinks/em_http"
require_relative "sinks/mysql2"
require_relative "sinks/pg"
require_relative "sinks/sqlite3"
require_relative "sinks/trilogy"

# :nocov:
