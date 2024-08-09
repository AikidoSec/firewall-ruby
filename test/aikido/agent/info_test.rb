# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::InfoTest < ActiveSupport::TestCase
  setup do
    @info = Aikido::Agent::Info.new
  end

  test "library_name is firewall-ruby" do
    assert_equal "firewall-ruby", @info.library_name
  end

  test "library_version matches the gem version" do
    assert_equal Aikido::Firewall::VERSION, @info.library_version
  end

  test "#ip_address returns the first non-loopback address reported" do
    addresses = [
      Addrinfo.ip("::1"),
      Addrinfo.ip("127.0.0.1"),
      Addrinfo.ip("192.168.0.1"),
      Addrinfo.ip("10.10.0.1")
    ]

    Socket.stub(:ip_address_list, addresses) do
      assert_equal "192.168.0.1", @info.ip_address
    end
  end

  test "#ip_address prefers IPv4 over IPv6" do
    addresses = [
      Addrinfo.ip("2a02:a018:14b:fe00:1823:e142:94cc:f088"),
      Addrinfo.ip("192.168.0.1")
    ]

    Socket.stub(:ip_address_list, addresses) do
      assert_equal "192.168.0.1", @info.ip_address
    end
  end

  test "#ip_address falls back on IPv6 if no non-lo IPv4 addresses are given" do
    addresses = [
      Addrinfo.ip("::1"),
      Addrinfo.ip("2a02:a018:14b:fe00:1823:e142:94cc:f088"),
      Addrinfo.ip("127.0.0.1")
    ]

    Socket.stub(:ip_address_list, addresses) do
      assert_equal "2a02:a018:14b:fe00:1823:e142:94cc:f088", @info.ip_address
    end
  end

  test "as_json includes the expected fields" do
    assert_equal @info.library_name, @info.as_json[:library]
    assert_equal @info.library_version, @info.as_json[:version]
    assert_equal @info.hostname, @info.as_json[:hostname]
    assert_equal @info.ip_address, @info.as_json[:ipAddress]
    assert_equal @info.os_name, @info.as_json.dig(:os, :name)
    assert_equal @info.os_version, @info.as_json.dig(:os, :version)

    assert_equal "", @info.as_json[:nodeEnv]
    assert_equal false, @info.as_json[:preventedPrototypePollution]

    # FIXME: Source the actual values for the following properties
    assert_equal false, @info.as_json[:dryMode]
    assert_equal false, @info.as_json[:serverless]
    assert_equal [], @info.as_json[:packages]
    assert_equal [], @info.as_json[:stack]
    assert_equal({}, @info.as_json[:incompatiblePackages])
  end
end
