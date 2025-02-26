# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::ShellInjectionScannerTest < ActiveSupport::TestCase
  def scan(command, input)
    Aikido::Zen::Scanners::ShellInjectionScanner.new(command, input).attack?
  end

  def assert_attack(command, input = command, reason = "[#{input}] was not blocked")
    assert scan(command, input), reason
  end

  def refute_attack(command, input = command, reason = "[#{input}] was blocked")
    refute scan(command, input), reason
  end

  test "input = ~ is detected as an attack " do
    assert_attack "ls ~", "~"
  end

  test "single characters are ignored" do
    refute_attack "ls `", "`"
    refute_attack "ls *", "*"
    refute_attack "ls a", "a"
  end

  test "no attack when empty input" do
    ["", " ", " " * 2, " " * 10].each { |input| refute_attack "ls", input }
  end

  test "no attack if the input is not part of the final command" do
    refute_attack "ls", "$(echo)"
  end

  test "no attack if input is longer than command" do
    refute_attack "`ls`", "`ls` `ls`"
  end

  test "it detects $(command)" do
    assert_attack "ls $(echo)", "$(echo)"
    assert_attack 'ls "$(echo)"', "$(echo)"
    assert_attack 'echo $(echo "Inner: $(echo "This is nested")")',
      '$(echo "Inner: $(echo "This is nested")")'

    refute_attack "ls '$(echo)'", "$(echo)"
    refute_attack "ls '$(echo \"Inner: $(echo \"This is nested\")\")'",
      '$(echo "Inner: $(echo "This is nested")")'
  end
end
