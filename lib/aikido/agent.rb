# frozen_string_literal: true

require_relative "firewall/version"

module Aikido
  module Agent
    VERSION = Firewall::VERSION
  end
end

require_relative "agent/current_request"
require_relative "agent/rails_engine" if defined?(::Rails)
