# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::StoredSSRFScannerTest < ActiveSupport::TestCase
  def assert_attack(hostname, addresses, reason = "`#{hostname}` was not blocked")
    scanner = Aikido::Zen::Scanners::StoredSSRFScanner.new(hostname, addresses)
    assert scanner.attack?, reason
  end

  def refute_attack(hostname, addresses, reason = "`#{hostname}` was blocked")
    scanner = Aikido::Zen::Scanners::StoredSSRFScanner.new(hostname, addresses)
    refute scanner.attack?, reason
  end

  test "allows hostnames that don't resolve to an address in the blocklist" do
    refute_attack "google.com", ["142.251.134.14"]
    refute_attack "aws.amazon.com", ["18.65.48.10", "18.65.48.20"]
  end

  test "stops hostnames that are trying to access the IMDS service" do
    assert_attack "trust-me-im-good.com", ["169.254.169.254"]
    assert_attack "trust-me-im-good.com", ["fd00:ec2::254"]
    assert_attack "trust-me-im-good.com", ["1.1.1.1", "169.254.169.254", "2.2.2.2"]
  end

  test "allows known hosts that resolve to dangerous addresses" do
    refute_attack "metadata.google.internal", ["169.254.169.254"]
    refute_attack "metadata.goog", ["169.254.169.254"]
  end
end
