# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "aikido/zen/ip_lists"

class Aikido::Zen::IPListsTest < ActiveSupport::TestCase
  setup do
    @directory = Dir.mktmpdir("ip_lists_test")
    @path = File.join(@directory, "list.ipls")
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  def write_and_reopen(ip_lists_data)
    Aikido::Zen::IPLists.write(@path, ip_lists_data)
    Aikido::Zen::IPLists.new(@path)
  end

  def ip_list(cidr, data: nil)
    ip = IPAddr.new(cidr)
    span = ip.to_range
    range = (span.begin.to_i..span.end.to_i)

    if ip.ipv4?
      {ipv4_ranges: [range], ipv6_ranges: [], data: data}
    else
      {ipv4_ranges: [], ipv6_ranges: [range], data: data}
    end
  end

  test ".write raises when the parent directory does not exist" do
    nested_path = File.join(@directory, "nested", "list.ipls")

    assert_raises(Errno::ENOENT) { Aikido::Zen::IPLists.write(nested_path, []) }
  end

  test ".new raises Errno::ENOENT when the file does not exist" do
    assert_raises(Errno::ENOENT) { Aikido::Zen::IPLists.new(@path) }
  end

  test ".new raises FormatError when the file does not look like an IP lists file" do
    Aikido::Zen::IPLists.write(@path, [ip_list("1.2.3.4/32")])

    # Corrupt the ipv4 section's header, right at the start of the file.
    bytes = File.binread(@path)
    bytes[0, 4] = "NOPE"
    File.binwrite(@path, bytes)

    assert_raises(Aikido::Zen::IPLists::FormatError) { Aikido::Zen::IPLists.new(@path) }
  end

  test "an empty array round-trips as an empty bundle" do
    bundle = write_and_reopen([])

    assert bundle.empty?
    assert_equal 0, bundle.size
  end

  test "round-trips many IP lists, in order, data included" do
    ip_lists_data = Array.new(10) { |i| ip_list("10.0.#{i}.0/24", data: "data#{i}") }

    bundle = write_and_reopen(ip_lists_data)

    refute bundle.empty?
    assert_equal 10, bundle.size

    ip_lists_data.each_index do |i|
      assert bundle[i].include?("10.0.#{i}.1")
      assert_equal "data#{i}", bundle[i].data
    end
  end

  test "#each yields every IPList, in the order they were written" do
    bundle = write_and_reopen([ip_list("10.0.0.0/24", data: "a"), ip_list("10.0.1.0/24", data: "b")])

    assert_equal %w[a b], bundle.map(&:data)
  end

  test "nil data round-trips as an empty string" do
    bundle = write_and_reopen([ip_list("10.0.0.0/24")])

    assert_equal "", bundle[0].data
  end

  test "an ipv6 IP list round-trips and matches ipv6 addresses" do
    bundle = write_and_reopen([ip_list("2001:db8::/32")])

    assert bundle[0].include?("2001:db8::1")
    refute bundle[0].include?("2001:db9::1")
  end

  test "an IP list with both ipv4 and ipv6 ranges matches both address families" do
    ipv4 = ip_list("10.0.0.0/24")
    ipv6 = ip_list("2001:db8::/32")
    mixed = {ipv4_ranges: ipv4[:ipv4_ranges], ipv6_ranges: ipv6[:ipv6_ranges], data: "mixed"}

    bundle = write_and_reopen([mixed])

    assert bundle[0].include?("10.0.0.1")
    assert bundle[0].include?("2001:db8::1")
    assert_equal "mixed", bundle[0].data
  end
end
