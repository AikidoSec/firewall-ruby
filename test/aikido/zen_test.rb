# frozen_string_literal: true

require "test_helper"

class Aikido::ZenTest < ActiveSupport::TestCase
  test "it has a version number" do
    refute_nil ::Aikido::Zen::VERSION
  end
end
