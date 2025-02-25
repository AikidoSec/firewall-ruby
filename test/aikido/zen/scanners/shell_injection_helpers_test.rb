# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::ShellInjectionScanner::HelpersTest < ActiveSupport::TestCase
  def assert_is_safely_encapsulated(command, user_input)
    assert Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.is_safely_encapsulated(command, user_input)
  end

  def refute_is_safely_encapsulated(command, user_input)
    refute Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.is_safely_encapsulated(command, user_input)
  end

  test "safe between single quotes" do
    assert_is_safely_encapsulated("echo '$USER'", "$USER")
    assert_is_safely_encapsulated("echo '`$USER'", "`USER")
  end

  test "single quote in single quotes" do
    refute_is_safely_encapsulated("echo ''USER'", "'USER")
  end

  test "dangerous chars between double quotes" do
    assert_is_safely_encapsulated 'echo "=USER"', "=USER"

    refute_is_safely_encapsulated 'echo "$USER"', "$USER"
    refute_is_safely_encapsulated 'echo "!USER"', "!USER"
    refute_is_safely_encapsulated 'echo "\`USER"', "`USER"
    refute_is_safely_encapsulated 'echo "\\USER"', "\\USER"
  end

  test "same user input multiple times" do
    assert_is_safely_encapsulated "echo '$USER' '$USER'", "$USER"

    refute_is_safely_encapsulated "echo \"$USER\" '$USER'", "$USER"
    refute_is_safely_encapsulated "echo \"$USER\" \"$USER\"", "$USER"
  end

  test "the first and last quote doesn't match" do
    refute_is_safely_encapsulated "echo '$USER\"", "$USER"
    refute_is_safely_encapsulated "echo \"$USER'", "$USER"
  end

  test "the first or last character is not an escape char" do
    refute_is_safely_encapsulated "echo $USER'", "$USER"
    refute_is_safely_encapsulated 'echo $USER"', "$USER"
  end

  test "user input does not occur in the command" do
    assert_is_safely_encapsulated "echo 'USER'", "$USER"
    assert_is_safely_encapsulated 'echo "USER"', "$USER"
  end
end
