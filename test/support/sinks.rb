# Databases
require "mysql2"
require "pg"
require "sqlite3"
require "trilogy"

# HTTP
require "net/http"
require "http"
require "httpx"
require "httpclient"
require "excon"
require "curb"
require "patron"
require "typhoeus"
require "async/http" if RUBY_VERSION >= "3.1"
require "em-http"

# Misc
require "action_controller"

# Keep this at the end of the file
require "aikido/zen/sinks"
