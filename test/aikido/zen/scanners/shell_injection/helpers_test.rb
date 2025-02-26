# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::ShellInjectionScanner::HelpersTest < ActiveSupport::TestCase
  def assert_is_safely_encapsulated(command, user_input)
    assert Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.is_safely_encapsulated(command, user_input)
  end

  def refute_is_safely_encapsulated(command, user_input)
    refute Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.is_safely_encapsulated(command, user_input)
  end

  def assert_contains_shell_syntax(command, user_input = command)
    assert Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.contains_shell_syntax(command, user_input)
  end

  def refute_contains_shell_syntax(command, user_input = command)
    refute Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.contains_shell_syntax(command, user_input)
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

  test "escape_string_regexp main" do
    result = Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.escape_string_regexp("\\ ^ $ * + ? . ( ) | { } [ ]")
    expected = "\\\\ \\^ \\$ \\* \\+ \\? \\. \\( \\) \\| \\{ \\} \\[ \\]"
    assert_equal expected, result
  end

  test "escapes - in a way compatible with PCRE" do
    result = Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.escape_string_regexp("foo - bar")
    expected = "foo \\x2d bar"
    assert_equal expected, result
  end

  test "escapes - in a way compatible with the Unicode flag" do
    regex = Regexp.new(Aikido::Zen::Scanners::ShellInjectionScanner::Helpers.escape_string_regexp("-"), Regexp::MULTILINE)
    assert_match regex, "-"
  end

  test "detects shell syntax" do
    refute_contains_shell_syntax ""
    refute_contains_shell_syntax "hello"
    refute_contains_shell_syntax "\n"
    refute_contains_shell_syntax "\n\n"

    assert_contains_shell_syntax "$(command)"
    assert_contains_shell_syntax "$(command arg arg)"
    assert_contains_shell_syntax "`command`"
    assert_contains_shell_syntax "\narg"
    assert_contains_shell_syntax "\targ"
    assert_contains_shell_syntax "\narg\n"
    assert_contains_shell_syntax "arg\n"
    assert_contains_shell_syntax "arg\narg"
    assert_contains_shell_syntax "rm -rf"
    assert_contains_shell_syntax "/bin/rm -rf"
    assert_contains_shell_syntax "/bin/rm"
    assert_contains_shell_syntax "/sbin/sleep"
    assert_contains_shell_syntax "/usr/bin/kill"
    assert_contains_shell_syntax "/usr/bin/killall"
    assert_contains_shell_syntax "/usr/bin/env"
    assert_contains_shell_syntax "/bin/ps"
    assert_contains_shell_syntax "/usr/bin/W"
  end

  test "it detects commands surrounded by separators" do
    assert_contains_shell_syntax 'find /path/to/search -type f -name "pattern" -exec rm {} \\\\;', "rm"
  end

  test "it detects commands with separator before" do
    assert_contains_shell_syntax "find /path/to/search -type f -name \"pattern\" | xargs rm", "rm"
  end

  test "it detects commands with separator after" do
    assert_contains_shell_syntax "rm arg", "rm"
    assert_contains_shell_syntax " rm\twhoami  ", "whoami"
    assert_contains_shell_syntax "\trm arg\t", "rm"
    assert_contains_shell_syntax "rm\t", "rm"
  end

  test "it checks if the same command occurs in the user input" do
    refute_contains_shell_syntax "find cp", "rm"
  end

  test "it treats colon as a command" do
    assert_contains_shell_syntax ":|echo", ":|"
    refute_contains_shell_syntax "https://www.google.com", "https://www.google.com"
  end

  test "it flags input as shell injection" do
    assert_contains_shell_syntax "command -disable-update-check -target https://examplx.com|curl+https://cde-123.abc.domain.com+%23 -json-export /tmp/5891/8526757.json -tags microsoft,windows,exchange,iis,gitlab,oracle,cisco,joomla -stats -stats-interval 3 -retries 3 -no-stdin",
      "https://examplx.com|curl+https://cde-123.abc.domain.com+%23"
  end
end
