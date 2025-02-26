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

  test "it detects `command`" do
    assert_attack "echo `echo`", "`echo`"
  end

  test "it checks unsafely quoted" do
    assert_attack "ls '$(echo)`", "$(echo)"
  end

  test "single quote between single quotes" do
    assert_attack "ls ''single quote''", "'single quote'"
  end

  test "it ignores escaped backticks" do
    refute_attack "binary --domain www.example\\`whoami\\`.com", "www.example`whoami`.com"
  end

  test "it does not allow special chars inside double quotes" do
    assert_attack "ls \"whatever$\"", "whatever$"
    assert_attack "ls \"whatever!\"", "whatever!"
    assert_attack "ls \"whatever`\"", "whatever`"
  end

  test "it does not allow semi" do
    assert_attack "ls whatever;", "whatever;"
    refute_attack "ls \"whatever;\"", "whatever;"
    refute_attack "ls 'whatever;'", "whatever;"
  end

  test "rm rf executed by using semi colon" do
    assert_attack "ls; rm -rf", "; rm -rf"
  end

  test "rm rf is flagged as shell injection" do
    assert_attack "rm -rf", "rm -rf"
  end

  test "it detects shell injection with chained commands using &&" do
    assert_attack "ls && rm -rf /", "&& rm -rf /"
  end

  test "it detects shell injection with OR logic using ||" do
    assert_attack "ls || echo 'malicious code'", "|| echo 'malicious code'"
  end

  test "it detects redirection attempts" do
    assert_attack "ls > /dev/null", "> /dev/null"
    assert_attack "cat file.txt > /etc/passwd", "> /etc/passwd"
  end

  test "it detects append redirection attempts" do
    assert_attack "echo 'data' >> /etc/passwd", ">> /etc/passwd"
  end

  test "it detects pipe character as potential shell injection" do
    assert_attack "cat file.txt | grep 'password'", "| grep 'password'"
  end

  test "it allows safe use of pipe character within quotes" do
    refute_attack "echo '|'", "|"
  end

  test "it detects nested command substitution" do
    assert_attack "echo $(cat $(ls))", "$(cat $(ls))"
  end

  test "it allows safe commands within single quotes" do
    refute_attack "echo 'safe command'", "safe command"
  end

  test "it detects unsafe use of variables" do
    assert_attack "echo $USER", "$USER"
    assert_attack "echo ${USER}", "${USER}"
    assert_attack 'echo "${USER}"', "${USER}"
  end

  test "it allows safe use of variables within quotes" do
    refute_attack "echo '$USER'", "$USER"
  end

  test "it detects subshell execution within backticks inside double quotes" do
    assert_attack "ls \"$(echo `whoami`)\"", "`whoami`"
  end

  test "it detects code injection with newline characters" do
    assert_attack "echo 'safe'\necho 'malicious'", "\necho 'malicious'"
  end

  test "it detects attempts to escape out of quotes" do
    assert_attack 'echo "safe"; echo "malicious"', '"; echo "malicious"'
  end

  test "it correctly handles whitespace in inputs" do
    refute_attack "ls", "   "
    assert_attack "ls ; rm -rf /", "; rm -rf /"
  end

  test "it detects file manipulation commands" do
    assert_attack "touch /tmp/malicious", "touch /tmp/malicious"
    assert_attack "mv /tmp/safe /tmp/malicious", "mv /tmp/safe /tmp/malicious"
  end

  test "allows commands with constants that resemble user input but are safely encapsulated" do
    refute_attack "echo 'userInput'", "userInput"
  end

  test "recognizes safe paths that include patterns similar to user input" do
    refute_attack "ls /constant/path/without/user/input/", "/constant/path/without/user/input/"
  end

  test "acknowledges safe use of special characters when properly encapsulated" do
    refute_attack 'echo ";"', ";"
    refute_attack 'echo "&&"', "&&"
    refute_attack 'echo "||"', "||"
  end

  test "treats encapsulated redirection and pipe symbols as safe" do
    refute_attack "echo 'data > file.txt'", "data > file.txt"
    refute_attack "echo 'find | grep'", "find | grep"
  end

  test "recognizes safe inclusion of special patterns within quotes as non-injections" do
    refute_attack "echo '$(command)'", "$(command)"
  end

  test "considers constants with semicolons as safe when clearly non-executable" do
    refute_attack "echo 'text; more text'", "text; more text"
  end

  test "acknowledges commands that look dangerous but are actually safe due to quoting" do
    refute_attack "echo '; rm -rf /'", "; rm -rf /"
    refute_attack "echo '&& echo malicious'", "&& echo malicious"
  end

  test "recognizes commands with newline characters as safe when encapsulated" do
    refute_attack "echo 'line1\nline2'", "line1\nline2"
  end

  test "accepts special characters in constants as safe when they do not lead to command execution" do
    refute_attack "echo '*'", "*"
    refute_attack "echo '?'", "?"
    refute_attack "echo '\\' ", "\\"
  end

  test "does not flag command with matching whitespace as injection" do
    refute_attack "ls -l", " " # A single space is just an argument separator, not user input
  end

  test "ignores commands where multiple spaces match user input" do
    refute_attack "ls   -l", "   " # Multiple spaces between arguments should not be considered injection
  end

  test "does not consider leading whitespace in commands as user input" do
    refute_attack "  ls -l", "  " # Leading spaces before the command are not user-controlled
  end

  test "treats trailing whitespace in commands as non-injection" do
    refute_attack "ls -l ", " " # Trailing space after the command is benign
  end

  test "recognizes spaces between quotes as non-injective" do
    refute_attack "echo ' ' ", " " # Space within quotes is part of the argument, not a separator
  end

  test "handles spaces within quoted arguments correctly" do
    refute_attack "command 'arg with spaces'", " " # Spaces within a quoted argument should not be flagged
  end

  test "correctly interprets spaces in mixed argument types" do
    refute_attack "command arg1 'arg with spaces' arg2", " " # Mixed argument types with internal spaces are safe
  end

  test "ignores spaces in commands with concatenated arguments" do
    refute_attack "command 'arg1'arg2'arg3'", " " # Lack of spaces in concatenated arguments is intentional and safe
  end

  test "does not flag spaces in commands with no arguments" do
    refute_attack "command", " " # No arguments mean spaces are irrelevant
  end

  test "considers spaces in environment variable assignments as safe" do
    refute_attack "ENV_VAR='value' command", " " # Spaces around environment variable assignments are not injections
  end

  test "new lines in commands are considered injections" do
    assert_attack "ls \nrm", "\nrm"
    assert_attack "ls \nrm -rf", "\nrm -rf"
  end

  test "new lines alone are not considered injections" do
    refute_attack "ls\n\n", "\n\n"
  end

  test "certain commands are always flagged as dangerous" do
    assert_attack "/bin/rm -rf", "/bin/rm -rf"
    assert_attack "rm -rf", "rm -rf"
    assert_attack "rm -rf /", "rm -rf /"
    assert_attack "sleep 10", "sleep 10"
    assert_attack "sleep 10 &", "sleep 10 &"
    assert_attack "shutdown -h now", "shutdown -h now"
    assert_attack "halt", "halt"
    assert_attack "poweroff", "poweroff"
    assert_attack "reboot", "reboot"
    assert_attack "reboot -f", "reboot -f"
    assert_attack "ifconfig", "ifconfig"
    assert_attack "ifconfig -a", "ifconfig -a"
    assert_attack "kill", "kill"
    assert_attack "killall", "killall"
    assert_attack "killall -9", "killall -9"
    assert_attack "chmod", "chmod"
    assert_attack "chmod 777", "chmod 777"
    assert_attack "chown", "chown"
    assert_attack "chown root", "chown root"
  end

  test "rm being part of other commands" do
    assert_attack "find /path/to/search -type f -name \"pattern\" | xargs rm", "rm"
    assert_attack "find /path/to/search -type f -name \"pattern\" -exec rm {} \\;", "rm"
    assert_attack "ls .|rm", "rm"
  end

  test "it ignores dangerous commands if they are part of a string" do
    refute_attack "binary sleepwithme", "sleepwithme"
    refute_attack "binary rm-rf", "rm-rf"
    refute_attack "term", "term"
    refute_attack "rm /files/rm.txt", "rm.txt"
  end

  test "it does not flag domain name as argument unless it contains backticks" do
    refute_attack "binary --domain www.example.com", "www.example.com"
    refute_attack "binary --domain https://www.example.com", "https://www.example.com"
    assert_attack "binary --domain www.example`whoami`.com", "www.example`whoami`.com"
    assert_attack "binary --domain https://www.example`whoami`.com", "https://www.example`whoami`.com"
  end

  test "it flags colon if used as a command" do
    assert_attack ":|echo", ":|"
    assert_attack ":| echo", ":|"
    assert_attack ": | echo", ": |"
  end

  test "it detects shell injection" do
    assert_attack "/usr/bin/kill", "/usr/bin/kill"
  end

  test "it detects shell injection with uppercase path" do
    assert_attack "/usr/bIn/kill", "/usr/bIn/kill"
  end

  test "it detects shell injection with uppercase command" do
    assert_attack "/bin/kill", "/bin/kill"
  end

  test "it detects shell injection with uppercase characters" do
    assert_attack "rm -rf", "rm -rf"
  end
end
