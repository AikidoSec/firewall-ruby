# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "aikido/zen/firewall/ip_lists"

class Aikido::Zen::Firewall::IPListsTest < ActiveSupport::TestCase
  setup do
    @directory = Dir.mktmpdir("firewall_ip_lists_test")
    @path = File.join(@directory, "list.ipls")
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  def raw_ip_list_data(key, cidrs)
    {"key" => key, "source" => "source-#{key}", "description" => "description-#{key}", "ips" => Array(cidrs)}
  end

  def write_and_reopen(raw_ip_lists_data)
    Aikido::Zen::Firewall::IPLists.write_from_json(@path, raw_ip_lists_data)
    Aikido::Zen::Firewall::IPLists.new(@path)
  end

  test ".write_from_json raises when the parent directory does not exist" do
    nested_path = File.join(@directory, "nested", "list.ipls")

    assert_raises(Errno::ENOENT) { Aikido::Zen::Firewall::IPLists.write_from_json(nested_path, []) }
  end

  test ".write_from_json treats nil raw_ip_lists_data as an empty list" do
    ip_lists = write_and_reopen(nil)

    assert ip_lists.empty?
  end

  test ".write_from_json raises when an address is neither ipv4 nor ipv6" do
    fake_address = Minitest::Mock.new
    fake_address.expect(:to_range, (0..0))
    fake_address.expect(:ipv4?, false)
    fake_address.expect(:ipv6?, false)

    IPAddr.stub :new, fake_address do
      assert_raises(ArgumentError) { Aikido::Zen::Firewall::IPLists.write_from_json(@path, [raw_ip_list_data("key1", "1.2.3.4")]) }
    end

    fake_address.verify
  end

  test ".new raises Errno::ENOENT when the file does not exist" do
    assert_raises(Errno::ENOENT) { Aikido::Zen::Firewall::IPLists.new(@path) }
  end

  test ".new raises FormatError when the file does not look like an IP lists file" do
    Aikido::Zen::Firewall::IPLists.write_from_json(@path, [raw_ip_list_data("key1", "1.2.3.4")])

    bytes = File.binread(@path)
    bytes[0, 4] = "NOPE"
    File.binwrite(@path, bytes)

    assert_raises(Aikido::Zen::IPLists::FormatError) { Aikido::Zen::Firewall::IPLists.new(@path) }
  end

  test "#empty? is true when there are no IP lists" do
    ip_lists = write_and_reopen([])

    assert ip_lists.empty?
  end

  test "#empty? is false when there is at least one IP list" do
    ip_lists = write_and_reopen([raw_ip_list_data("key1", "10.0.0.0/24")])

    refute ip_lists.empty?
  end

  test "#include? is true for an ip covered by any IP list" do
    raw_ip_lists_data = [raw_ip_list_data("key1", "10.0.0.0/24"), raw_ip_list_data("key2", "10.0.1.0/24")]

    ip_lists = write_and_reopen(raw_ip_lists_data)

    assert ip_lists.include?("10.0.0.1")
    assert ip_lists.include?("10.0.1.1")
    refute ip_lists.include?("192.168.0.1")
  end

  test "#include? is true for an ip covered by an ipv6 IP list" do
    ip_lists = write_and_reopen([raw_ip_list_data("key1", "2001:db8::/32")])

    assert ip_lists.include?("2001:db8::1")
    refute ip_lists.include?("2001:db9::1")
  end

  test "#include? is true for either family when a single raw IP list mixes ipv4 and ipv6 CIDRs" do
    ip_lists = write_and_reopen([raw_ip_list_data("key1", ["10.0.0.0/24", "2001:db8::/32"])])

    assert ip_lists.include?("10.0.0.1")
    assert ip_lists.include?("2001:db8::1")
  end

  test "#matching_ip_lists does not return a redundant merged twin for a single raw IP list" do
    ip_lists = write_and_reopen([raw_ip_list_data("key1", "10.0.0.0/24")])

    assert_equal 1, ip_lists.matching_ip_lists("10.0.0.1").size
  end

  test "#matching_ip_lists is empty when nothing matches" do
    ip_lists = write_and_reopen([raw_ip_list_data("key1", "10.0.0.0/24")])

    assert_equal [], ip_lists.matching_ip_lists("192.168.0.1")
    assert_equal [], ip_lists.matching_ip_lists(nil)
  end

  test "#matching_ip_lists identifies the one IP list an ip came from" do
    raw_ip_lists_data = [raw_ip_list_data("key1", "10.0.0.0/24"), raw_ip_list_data("key2", "10.0.1.0/24")]

    ip_lists = write_and_reopen(raw_ip_lists_data)
    matches = ip_lists.matching_ip_lists("10.0.0.1")

    assert_equal 1, matches.size
    assert_equal "key1", matches.first.key
    assert_equal "source-key1", matches.first.source
    assert_equal "description-key1", matches.first.description
  end

  test "#matching_ip_lists identifies every IP list when ranges overlap" do
    raw_ip_lists_data = [
      raw_ip_list_data("key1", "10.0.0.0/24"),
      raw_ip_list_data("key2", "10.0.0.128/25"),
      raw_ip_list_data("key3", "192.168.0.0/24")
    ]

    ip_lists = write_and_reopen(raw_ip_lists_data)
    matches = ip_lists.matching_ip_lists("10.0.0.200")

    assert_equal %w[key1 key2], matches.map(&:key).sort
  end

  test "an ip covered by an unattributed gap in the merged copy still resolves correctly" do
    # key1 and key2 are adjacent (not overlapping) and merge into one
    # contiguous copy covering both /24s; an address in key2 only should
    # still say yes on the fast (merged) path, and correctly attribute
    # only to key2, not key1, on the fallback path.
    raw_ip_lists_data = [raw_ip_list_data("key1", "10.0.0.0/24"), raw_ip_list_data("key2", "10.0.1.0/24")]

    ip_lists = write_and_reopen(raw_ip_lists_data)

    assert ip_lists.include?("10.0.1.5")
    assert_equal ["key2"], ip_lists.matching_ip_lists("10.0.1.5").map(&:key)
  end
end
