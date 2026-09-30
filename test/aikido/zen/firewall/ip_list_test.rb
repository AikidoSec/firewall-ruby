# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Firewall::IPListTest < ActiveSupport::TestCase
  DEFAULT_IP_LIST = {
    "key" => "key",
    "source" => "source",
    "description" => "description",
    "ips" => [
      "192.168.0.0/24",
      "10.0.0.0/8",
      "172.16.0.0/12",
      "203.0.113.0/24",
      "198.51.100.0/25",
      "2001:db8::/32",
      "2001:db8:1234::/48",
      "2001:db8:abcd:0012::/64",
      "fd00::/8",
      "fe80::/10"
    ]
  }

  test "create IP list from JSON" do
    ip_list = Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)

    assert_kind_of Aikido::Zen::Firewall::IPList, ip_list

    assert_equal "key", ip_list.key
    assert_equal "source", ip_list.source
    assert_equal "description", ip_list.description
  end

  test "#inspect includes the key" do
    ip_list = Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)

    assert_equal "#<Aikido::Zen::Firewall::IPList key>", ip_list.inspect
  end

  test "creating an IP list raises InternalsError if the native matcher cannot be created" do
    Aikido::Zen::Internals.stub :ip_matcher_create_native, FFI::Pointer::NULL do
      err = assert_raises Aikido::Zen::InternalsError do
        Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)
      end

      assert_equal %(Zen could not create an IP matcher due to a problem calling ip_matcher_create in the library `#{Aikido::Zen::Internals.libzen_name}'), err.message
    end
  end

  test "creating an IP list raises ArgumentError if any network is invalid" do
    data = DEFAULT_IP_LIST.merge("ips" => ["10.0.0.0/8", "not-a-network", "10.0.0.0/33"])

    error = assert_raises ArgumentError do
      Aikido::Zen::Firewall::IPList.from_json(data)
    end

    assert_equal %(IP list "key" has 2 invalid network(s), more than the 0 allowed), error.message
  end

  test "creating an IP list tolerates up to max_rejected_count invalid networks" do
    args = {key: "key", source: "source", description: "description", ips: ["10.0.0.0/8", "not-a-network", "10.0.0.0/33"]}

    ip_list = Aikido::Zen::Firewall::IPList.new(**args, max_rejected_count: 2)
    assert ip_list.include?("10.1.2.3")

    error = assert_raises ArgumentError do
      Aikido::Zen::Firewall::IPList.new(**args, max_rejected_count: 1)
    end

    assert_equal %(IP list "key" has 2 invalid network(s), more than the 1 allowed), error.message
  end

  test "#include? is true if the ip address is included" do
    ip_list = Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)

    [
      "192.168.0.1",
      "192.168.0.42",
      "192.168.0.200",
      "10.0.0.1",
      "10.1.2.3",
      "10.255.255.254",
      "172.16.0.1",
      "172.20.10.5",
      "172.31.255.254",
      "203.0.113.1",
      "203.0.113.50",
      "203.0.113.200",
      "198.51.100.1",
      "198.51.100.60",
      "198.51.100.126",
      "2001:db8::1",
      "2001:db8::abcd",
      "2001:db8::1234:5678",
      "2001:db8:1234::1",
      "2001:db8:1234:0:1::1",
      "2001:db8:1234:ffff:ffff:ffff:ffff:ffff",
      "2001:db8:abcd:12::1",
      "2001:db8:abcd:12::10",
      "2001:db8:abcd:12::ffff",
      "fd00::1",
      "fd12:3456:789a::1",
      "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
      "fe80::1",
      "fe80::1234",
      "fe80::ffff:ffff:ffff:ffff"
    ].each do |ip|
      assert ip_list.include?(ip)
    end
  end

  test "#include? is false if the ip address is not included" do
    ip_list = Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)

    [
      "1.1.1.1",
      "8.8.4.4",
      "9.9.9.9",
      "142.250.72.14",
      "151.101.1.69",
      "2606:4700:4700::1111",
      "2606:4700:4700::1001",
      "2620:fe::fe",
      "2620:119:35::35",
      "2a03:2880:f11c:8083::face:b00c"
    ].each do |ip|
      refute ip_list.include?(ip)
    end
  end

  test "#include? matches IPv4-mapped IPv6 addresses against IPv4 networks" do
    ip_list = Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)

    assert ip_list.include?("::ffff:192.168.0.1")
  end

  test "#include? does not match IPv4-mapped IPv6 addresses of IPv4 addresses outside the networks" do
    ip_list = Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)

    refute ip_list.include?("::ffff:8.8.8.8")
  end

  test "#include? is false for nil" do
    ip_list = Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)

    refute ip_list.include?(nil)
  end

  test "#include? is false for strings that are not IP addresses" do
    ip_list = Aikido::Zen::Firewall::IPList.from_json(DEFAULT_IP_LIST)

    ["", "not-an-ip", "::zzz", "999.1.1.1", "1.2.3.4:80"].each do |ip|
      refute ip_list.include?(ip), "expected #{ip.inspect} not to be included"
    end
  end
end
