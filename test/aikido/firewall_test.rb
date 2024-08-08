# frozen_string_literal: true

require "test_helper"

class Aikido::TestFirewall < ActiveSupport::TestCase
  test "it has a version number" do
    refute_nil ::Aikido::Firewall::VERSION
  end
end
