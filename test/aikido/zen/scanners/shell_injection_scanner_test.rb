# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::ShellInjectionScannerTest < ActiveSupport::TestCase
  def scan(command, input)
    Aikido::Zen::Scanners::ShellInjectionScanner.new(command, input).attack?
  end
end
