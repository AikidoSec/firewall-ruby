# frozen_string_literal: true

require "test_helper"
require "simpleidn"

class Aikido::Zen::RuntimeSettings::DomainsTest < ActiveSupport::TestCase
  DEFAULT_DOMAINS = [
    {
      "hostname" => "safe.example.com",
      "mode" => "allow"
    },
    {
      "hostname" => "evil.example.com",
      "mode" => "block"
    },
    {
      "hostname" => "allowed-site.com",
      "mode" => "allow"
    },
    {
      "hostname" => "böse.example.com",
      "mode" => "block"
    },
    {
      "hostname" => "münchen.example.com",
      "mode" => "block"
    },
    {
      "hostname" => "münchen-allowed.example.com",
      "mode" => "allow"
    }
  ]

  test "create domains list from JSON" do
    domains = Aikido::Zen::RuntimeSettings::Domains.from_json(DEFAULT_DOMAINS)

    assert_kind_of Aikido::Zen::RuntimeSettings::Domains, domains

    assert 5, domains.size

    DEFAULT_DOMAINS.each do |domain_hash|
      hostname = domain_hash["hostname"]
      mode = domain_hash["mode"].to_sym

      assert_includes domains, hostname
      assert_equal mode, domains[hostname].mode
    end
  end

  test "lookup returns domain settings" do
    domains = Aikido::Zen::RuntimeSettings::Domains.from_json(DEFAULT_DOMAINS)

    DEFAULT_DOMAINS.each do |domain_hash|
      hostname = domain_hash["hostname"]
      mode = domain_hash["mode"].to_sym

      assert_includes domains, hostname

      domain = domains[hostname]

      refute_nil domain
      assert_kind_of Aikido::Zen::RuntimeSettings::DomainSettings, domain
      assert_equal mode, domain.mode
    end
  end

  test "lookup returns default domain settings for unknown domains" do
    domains = Aikido::Zen::RuntimeSettings::Domains.from_json(DEFAULT_DOMAINS)

    refute_includes domains, "unknown"

    domain = domains["unknown"]

    refute_nil domain
    assert_kind_of Aikido::Zen::RuntimeSettings::DomainSettings, domain
    assert_equal Aikido::Zen::RuntimeSettings::DomainSettings.none, domain
  end

  test "lookup returns the domain settings independent of case" do
    domains = Aikido::Zen::RuntimeSettings::Domains.from_json(DEFAULT_DOMAINS)

    DEFAULT_DOMAINS.each do |domain_hash|
      hostname = domain_hash["hostname"].swapcase
      mode = domain_hash["mode"].to_sym

      assert_includes domains, hostname
      assert_equal mode, domains[hostname].mode
    end
  end

  test "lookup returns the domain settings when the domain containing unicode characters and the request domain is Punycode-encoded" do
    domains = Aikido::Zen::RuntimeSettings::Domains.from_json(DEFAULT_DOMAINS)

    DEFAULT_DOMAINS.each do |domain_hash|
      hostname = SimpleIDN.to_ascii(domain_hash["hostname"])
      mode = domain_hash["mode"].to_sym

      assert_includes domains, hostname
      assert_equal mode, domains[hostname].mode
    end
  end
end
