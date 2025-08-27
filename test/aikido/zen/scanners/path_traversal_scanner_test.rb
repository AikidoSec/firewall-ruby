# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::PathTraversalScannerTest < ActiveSupport::TestCase
  def assert_attack(filepath, input = filepath, reason = "#{input} was not blocked")
    assert scan(filepath, input), reason
  end

  def refute_attack(filepath, input = filepath, reason = "#{input} was blocked")
    refute scan(filepath, input), reason
  end

  def scan(filepath, input = query)
    Aikido::Zen::Scanners::PathTraversalScanner.new(filepath, input).attack?
  end

  test "no path traversal" do
    refute_attack "/some-directory/sub-folder/file.txt", "/sub-folder/file.txt"
  end

  test "ignores input with length <= 1" do
    refute_attack ""
    refute_attack "a"
    refute_attack "abcd", ""
    refute_attack "abcd", "a"
  end

  test "ignores in case the input is longer than the filepath" do
    refute_attack "1", "12"
    refute_attack "base-string", "base-string-plus-words"
  end

  test "ignores in case the input not contained by filepath" do
    refute_attack "1", "a"
    refute_attack "base-string", "base-string".reverse
  end

  test "same as user input" do
    refute_attack "file.txt", "file.txt"
  end

  test "with directory before" do
    refute_attack "directory/file.txt", "file.txt"
    refute_attack "directory/file.txt", "directory/file.txt"
  end

  test "it flags bad inputs" do
    # inputs with ../
    assert_attack "../file.txt", "../"
    assert_attack "../file.txt", "../file.txt"
    assert_attack "../../file.txt", "../../"
    assert_attack "../../file.txt", "../../file.txt"

    # inputs with ..\\
    assert_attack "..\\file.txt", "..\\"
    assert_attack "..\\file.txt", "..\\file.txt"
    assert_attack "..\\..\\file.txt", "..\\..\\"
    assert_attack "..\\..\\file.txt", "..\\..\\file.txt"

    # inputs with ./../
    assert_attack "./../file.txt", "./../"
    assert_attack "./../file.txt", "./../file.txt"
    assert_attack "./../../file.txt", "./../../"
    assert_attack "./../../file.txt", "./../../file.txt"
  end

  test "linux paths" do
    refute_attack "/etc/passwd", "/etc/"
    assert_attack "/etc/passwd", "/etc/passwd"
    assert_attack "/etc/../etc/passwd", "/etc/../etc/passwd"
    assert_attack "/home/user/file.txt", "/home/user"
  end

  test "possible bypasses" do
    assert_attack "/./etc/passwd", "/./etc/passwd"
    assert_attack "/./././root/file.txt", "/./././root/"
    assert_attack "/./././root/file.txt", "/./././root/file.txt"
  end

  test "does not detect if user input path contains no filename or subfolder" do
    refute_attack "/etc/app/test.txt", "/etc/"
    refute_attack "/etc/app/", "/etc/"
    refute_attack "/etc/app/", "/etc"
    refute_attack "/etc/", "/etc/"
    refute_attack "/etc", "/etc"
    refute_attack "/var/a", "/var/"
    refute_attack "/var/a", "/var/b"
    refute_attack "/var/a", "/var/b/test.txt"
  end

  test "it does dected if user input path contains a filename or subfolder" do
    assert_attack "/etc/app/file.txt", "/etc/app"
    assert_attack "/etc/app/file.txt", "/etc/app/file.txt"
    assert_attack "/var/backups/file.txt", "/var/backups"
    assert_attack "/var/backups/file.txt", "/var/backups/file.txt"
    assert_attack "/var/a", "/var/a"
    assert_attack "/var/a/b", "/var/a"
    assert_attack "/var/a/b/test.txt", "/var/a"
  end
end
