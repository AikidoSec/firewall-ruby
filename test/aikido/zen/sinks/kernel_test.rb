# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::KernelTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  SOME_ENV = {"foo" => "bar"}

  def assert_shell_injection_attack(attack_string = "$(whoami)", &block)
    set_context_from_request_to "/?arg=#{attack_string}"

    assert_attack Aikido::Zen::Attacks::ShellInjectionAttack, &block
  end

  def refute_shell_injection_attack(attack_string = "$(whoami)", &block)
    set_context_from_request_to "/?arg=#{attack_string}"

    refute_attack(&block)
  end

  test "system works normally" do
    assert system("ls")
    assert system(SOME_ENV, "ls")
    assert system("ls", unsetenv_others: true)
    assert system(SOME_ENV, "ls", unsetenv_others: true)

    assert system("ls -a")
    assert system(SOME_ENV, "ls -a")
    assert system("ls -a", unsetenv_others: true)
    assert system(SOME_ENV, "ls -a", unsetenv_others: true)

    assert system("ls", "-a")
    assert system(SOME_ENV, "ls", "-a")
    assert system("ls", "-a", unsetenv_others: true)
    assert system(SOME_ENV, "ls", "-a", unsetenv_others: true)

    refute system("invalid-command-123")

    system("echo", "$(whoami)") # harmless call: result is "$(whoami)"
  end

  test "attacks are detected" do
    assert_shell_injection_attack "$(whoami)" do
      system("echo $(whoami)")
    end

    assert_shell_injection_attack "$(whoami)" do
      system(SOME_ENV, "echo $(whoami)")
    end
  end
end
