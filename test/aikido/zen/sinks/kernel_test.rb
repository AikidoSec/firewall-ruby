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
    assert system("echo")
    assert system(SOME_ENV, "echo")
    assert system("echo", unsetenv_others: true)
    assert system(SOME_ENV, "echo", unsetenv_others: true)

    assert system("echo -n")
    assert system(SOME_ENV, "echo -n")
    assert system("echo -n", unsetenv_others: true)
    assert system(SOME_ENV, "echo -n", unsetenv_others: true)

    assert system("echo", "-n")
    assert system(SOME_ENV, "echo", "-n")
    assert system("echo", "-n", unsetenv_others: true)
    assert system(SOME_ENV, "echo", "-n", unsetenv_others: true)

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

    assert_spawn_runs_normally { spawn("echo") }
    assert_spawn_runs_normally { spawn(SOME_ENV, "echo") }
    assert_spawn_runs_normally { spawn("echo", unsetenv_others: true) }
    assert_spawn_runs_normally { spawn(SOME_ENV, "echo", unsetenv_others: true) }

    assert_spawn_runs_normally { spawn("echo -n") }
    assert_spawn_runs_normally { spawn(SOME_ENV, "echo -n") }
    assert_spawn_runs_normally { spawn("echo -n", unsetenv_others: true) }
    assert_spawn_runs_normally { spawn(SOME_ENV, "echo -n", unsetenv_others: true) }

    assert_spawn_runs_normally { spawn("echo", "-n") }
    assert_spawn_runs_normally { spawn(SOME_ENV, "echo", "-n") }
    assert_spawn_runs_normally { spawn("echo", "-n", unsetenv_others: true) }
    assert_spawn_runs_normally { spawn(SOME_ENV, "echo", "-n", unsetenv_others: true) }

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

  test "backtick works normally" do
    result = `echo -n hello`
    assert_equal "hello", result

    result = `echo '$(whoami)'`
    assert_equal "$(whoami)\n", result

    assert_raises Errno::ENOENT do
      `invalid-command-123`
    end
  end

  test "attacks through backtick are detected" do
    assert_shell_injection_attack "$(whoami)" do
      `echo $(whoami)`
    end
  end

  test "%x() works normally" do
    result = %x(echo -n hello) # rubocop:disable Style/CommandLiteral
    assert_equal "hello", result

    result = %x(echo '$(whoami)') # rubocop:disable Style/CommandLiteral
    assert_equal "$(whoami)\n", result

    assert_raises Errno::ENOENT do
      %x(invalid-command-123) # rubocop:disable Style/CommandLiteral
    end
  end

  test "attacks through %x() are detected" do
    assert_shell_injection_attack "$(whoami)" do
      %x(echo $(whoami)) # rubocop:disable Style/CommandLiteral
    end
  end
end
