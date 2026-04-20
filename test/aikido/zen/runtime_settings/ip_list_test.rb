# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RuntimeSettings::IPListTest < ActiveSupport::TestCase
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
    ip_list = Aikido::Zen::RuntimeSettings::IPList.from_json(DEFAULT_IP_LIST)

    assert_kind_of Aikido::Zen::RuntimeSettings::IPList, ip_list

    assert_equal "key", ip_list.key
    assert_equal "source", ip_list.source
    assert_equal "description", ip_list.description
    assert_equal 10, ip_list.ips.size
    assert_equal 5, ip_list.ipv4_ranges.size
    assert_equal 5, ip_list.ipv6_ranges.size
  end

  test "#include? is true if the ip address is included" do
    ip_list = Aikido::Zen::RuntimeSettings::IPList.from_json(DEFAULT_IP_LIST)

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
    ip_list = Aikido::Zen::RuntimeSettings::IPList.from_json(DEFAULT_IP_LIST)

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
end
