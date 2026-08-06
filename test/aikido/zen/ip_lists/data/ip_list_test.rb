# frozen_string_literal: true

require "test_helper"
require "aikido/zen/ip_lists/data/ip_list"

class Aikido::Zen::IPLists::Data::IPListTest < ActiveSupport::TestCase
  def reader_with_ranges(family:, ranges:)
    io = StringIO.new(+"", "r+")
    io.set_encoding(Encoding::BINARY)
    Aikido::Zen::IPLists::Data::IPList::Writer.new(family: family).write(io, ranges)
    Aikido::Zen::IPLists::Data::IPList::Reader.new(family: family, io: io)
  end

  def ip_list(ipv4_ranges:, ipv6_ranges:)
    Aikido::Zen::IPLists::Data::IPList.new(
      ipv4_reader: reader_with_ranges(family: :ipv4, ranges: ipv4_ranges),
      ipv6_reader: reader_with_ranges(family: :ipv6, ranges: ipv6_ranges)
    )
  end

  test "#include? is true for an ipv4 address in the ipv4 ranges" do
    list = ip_list(ipv4_ranges: [(IPAddr.new("10.0.0.0").to_i..IPAddr.new("10.255.255.255").to_i)], ipv6_ranges: [])

    assert list.include?("10.1.2.3")
    assert list.include?(IPAddr.new("10.1.2.3"))
    refute list.include?("11.0.0.0")
  end

  test "#include? is true for an ipv6 address in the ipv6 ranges" do
    start_ip = IPAddr.new("2001:db8::").to_i
    end_ip = IPAddr.new("2001:db8:ffff:ffff:ffff:ffff:ffff:ffff").to_i

    list = ip_list(ipv4_ranges: [], ipv6_ranges: [(start_ip..end_ip)])

    assert list.include?("2001:db8::1")
    assert list.include?(IPAddr.new("2001:db8::1"))
    refute list.include?("2001:db9::1")
  end

  test "an ipv4 address never matches the ipv6 ranges and vice versa" do
    ipv4_ranges = [(IPAddr.new("10.0.0.0").to_i..IPAddr.new("10.255.255.255").to_i)]
    ipv6_ranges = [(IPAddr.new("2001:db8::").to_i..IPAddr.new("2001:db8:ffff:ffff:ffff:ffff:ffff:ffff").to_i)]

    list = ip_list(ipv4_ranges: ipv4_ranges, ipv6_ranges: ipv6_ranges)

    assert list.include?("10.1.2.3")
    assert list.include?("2001:db8::1")
  end

  test "#include? is false for nil" do
    list = ip_list(ipv4_ranges: [], ipv6_ranges: [])

    refute list.include?(nil)
  end

  test "#include? is false for an unparseable address" do
    list = ip_list(ipv4_ranges: [], ipv6_ranges: [])

    refute list.include?("not an ip address")
  end
end
