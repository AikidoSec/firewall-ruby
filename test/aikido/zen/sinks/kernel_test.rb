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

  test "spawn works normally" do
    def assert_spawn_runs_normally(&block)
      assert_nothing_raised do
        pid = yield
        Process.wait(pid)
      end
    end

    assert_spawn_runs_normally { spawn("ls") }
    assert_spawn_runs_normally { spawn(SOME_ENV, "ls") }
    assert_spawn_runs_normally { spawn("ls", unsetenv_others: true) }
    assert_spawn_runs_normally { spawn(SOME_ENV, "ls", unsetenv_others: true) }

    assert_spawn_runs_normally { spawn("ls -a") }
    assert_spawn_runs_normally { spawn(SOME_ENV, "ls -a") }
    assert_spawn_runs_normally { spawn("ls -a", unsetenv_others: true) }
    assert_spawn_runs_normally { spawn(SOME_ENV, "ls -a", unsetenv_others: true) }

    assert_spawn_runs_normally { spawn("ls", "-a") }
    assert_spawn_runs_normally { spawn(SOME_ENV, "ls", "-a") }
    assert_spawn_runs_normally { spawn("ls", "-a", unsetenv_others: true) }
    assert_spawn_runs_normally { spawn(SOME_ENV, "ls", "-a", unsetenv_others: true) }

    assert_raises Errno::ENOENT do
      pid spawn("invalid-command-123")
      Process.wait pid # we only wait for the latest command, hopefully all the other commands have alread finished
    end
  end

  test "attacks through calls to `system` are detected" do
    assert_shell_injection_attack "$(whoami)" do
      system("echo $(whoami)")
    end

    assert_shell_injection_attack "$(whoami)" do
      system(SOME_ENV, "echo $(whoami)")
    end

    assert_shell_injection_attack "$(whoami)" do
      system("echo $(whoami)", unsetenv_others: true)
    end

    assert_shell_injection_attack "$(whoami)" do
      system(SOME_ENV, "echo $(whoami)", unsetenv_others: true)
    end
  end

  test "attacks through calls to `spawn` are detected" do
    assert_shell_injection_attack "$(whoami)" do
      spawn "echo $(whoami)"
    end

    assert_shell_injection_attack "$(whoami)" do
      spawn SOME_ENV, "echo $(whoami)"
    end

    assert_shell_injection_attack "$(whoami)" do
      spawn "echo $(whoami)", unsetenv_others: true
    end

    assert_shell_injection_attack "$(whoami)" do
      spawn SOME_ENV, "echo $(whoami)", unsetenv_others: true
    end
  end
end
