# frozen_string_literal: true

require "test_helper"

class Aikido::InternalsTest < ActiveSupport::TestCase
  Internals = Aikido::Zen::Internals

  test "it has a libzen version number" do
    refute_nil Aikido::Zen::LIBZEN_VERSION
  end

  test ".detect_sql_injection_native is attached" do
    assert Internals.singleton_methods.include?(:detect_sql_injection_native)
  end

  test ".detect_sql_injection is defined" do
    assert Internals.methods.include?(:detect_sql_injection)
  end

  test ".detect_sql_injection can detect SQL injection" do
    assert Internals.detect_sql_injection(
      "SELECT * FROM users WHERE id = '' OR 1=1 -- '",
      "' OR 1=1 -- ",
      Aikido::Zen::SQL::Dialects.fetch(:mysql)
    )
  end

  test ".idor_analyze_sql_native is attached" do
    assert Internals.singleton_methods.include?(:idor_analyze_sql_native)
  end

  test ".idor_free_string_native is attached" do
    assert Internals.singleton_methods.include?(:idor_free_string_native)
  end

  test ".idor_analyze_sql is defined" do
    assert Internals.methods.include?(:idor_analyze_sql)
  end

  test ".idor_analyze_sql can analyze SELECT queries" do
    result = Internals.idor_analyze_sql("SELECT * FROM users u WHERE u.tenant_id = $1", 9)
    assert_equal(
      [
        {
          "kind" => "select",
          "tables" => [
            {
              "name" => "users",
              "alias" => "u"
            }
          ],
          "filters" => [
            {
              "table" => "u",
              "column" => "tenant_id",
              "value" => "$1",
              "is_placeholder" => true
            }
          ]
        }
      ],
      result
    )
  end

  test ".idor_analyze_sql can analyze INSERT queries" do
    result = Internals.idor_analyze_sql("INSERT INTO users (name, tenant_id) VALUES ('John', $1)", 9)
    assert_equal(
      [
        {
          "kind" => "insert",
          "tables" => [
            {
              "name" => "users"
            }
          ],
          "filters" => [],
          "insert_columns" => [
            [
              {
                "column" => "name",
                "value" => "John",
                "is_placeholder" => false
              },
              {
                "column" => "tenant_id",
                "value" => "$1",
                "is_placeholder" => true
              }
            ]
          ]
        }
      ],
      result
    )
  end

  test ".idor_analyze_sql returns a parse error value when the query cannot be parsed" do
    result = Internals.idor_analyze_sql("THIS IS NOT SQL", Aikido::Zen::SQL::Dialects.fetch(:mysql))

    assert_equal(
      {"error" => "sql parser error: Expected: an SQL statement, found: THIS at Line: 1, Column: 1"},
      result
    )
  end

  test ".ip_matcher_create_native is attached" do
    assert Internals.singleton_methods.include?(:ip_matcher_create_native)
  end

  test ".ip_matcher_has_native is attached" do
    assert Internals.singleton_methods.include?(:ip_matcher_has_native)
  end

  test ".ip_matcher_memory_size_native is attached" do
    assert Internals.singleton_methods.include?(:ip_matcher_memory_size_native)
  end

  test ".ip_matcher_rejected_count_native is attached" do
    assert Internals.singleton_methods.include?(:ip_matcher_rejected_count_native)
  end

  test ".ip_matcher_free_native is attached" do
    assert Internals.singleton_methods.include?(:ip_matcher_free_native)
  end

  test "IPMatcher reports no rejected networks when every network is valid" do
    matcher = Internals::IPMatcher.new(["10.0.0.0/8", "2001:db8::/32"])

    assert_equal 0, matcher.rejected_count
  end

  test "IPMatcher counts the networks it rejected" do
    matcher = Internals::IPMatcher.new(["10.0.0.0/8", "not-a-network", "10.0.0.0/33", "2001:db8::/32"])

    assert_equal 2, matcher.rejected_count
    assert matcher.include?("10.1.2.3")
    refute matcher.include?("192.0.2.1")
  end

  test "an empty IPMatcher has nothing rejected" do
    matcher = Internals::IPMatcher.new([])

    assert_equal 0, matcher.rejected_count
    refute matcher.include?("10.1.2.3")
  end

  test "IPMatcher ignores invalid networks and matches the valid ones" do
    matcher = Internals::IPMatcher.new([
      "192.168.0.0/24", "foobar", "0.a.0.0/32", "123.123.123.123/1999", "", ",,,", "192.168.0.255"
    ])

    assert_equal 5, matcher.rejected_count

    assert matcher.include?("192.168.0.1")
    assert matcher.include?("192.168.0.255")
    refute matcher.include?("10.0.0.1")
    refute matcher.include?("foobar")
    refute matcher.include?("")
  end

  test "IPMatcher ignores the host bits of a network" do
    matcher = Internals::IPMatcher.new(["192.168.0.123/24", "2001:db8:1::beef/48"])

    assert matcher.include?("192.168.0.1")
    refute matcher.include?("192.168.1.1")
    assert matcher.include?("2001:db8:1:ffff::1")
    refute matcher.include?("2001:db8:2::1")
  end

  test "IPMatcher matches on every IPv4 prefix length boundary" do
    {
      "123.2.0.2/0" => ["1.1.1.1", true],
      "123.2.0.2/1" => ["1.1.1.1", true],
      "123.2.0.2/2" => ["1.1.1.1", false],
      "123.2.0.2/15" => ["123.3.0.1", true],
      "123.2.0.2/16" => ["123.3.0.1", false],
      "123.2.0.2/30" => ["123.2.0.1", true],
      "123.2.0.2/31" => ["123.2.0.1", false],
      "123.2.0.2/32" => ["123.2.0.2", true]
    }.each do |network, (ip, expected)|
      assert_equal expected, Internals::IPMatcher.new([network]).include?(ip), "#{ip} in #{network}"
    end
  end

  test "IPMatcher with 0.0.0.0/0 and ::/0 matches every address" do
    matcher = Internals::IPMatcher.new(["0.0.0.0/0", "::/0"])

    ["1.2.3.4", "255.255.255.255", "::1", "2002:db8::1", "::ffff:1234"].each do |ip|
      assert matcher.include?(ip), ip
    end
  end

  test "IPMatcher matches networks at the end of the address space" do
    matcher = Internals::IPMatcher.new(["224.0.0.0/4", "240.0.0.0/4", "e000::/4", "f000::/4"])

    assert matcher.include?("224.0.0.1")
    assert matcher.include?("255.255.255.255")
    refute matcher.include?("223.255.255.255")
    assert matcher.include?("e000::1")
    assert matcher.include?("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
    refute matcher.include?("dfff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
  end

  test "IPMatcher strips the zone from scoped IPv6 addresses" do
    matcher = Internals::IPMatcher.new(["fe80::/10", "::1/128"])

    assert matcher.include?("fe80::1%eth0")
    assert matcher.include?("[fe80::1%eth0]")
    assert matcher.include?("::1%lo")
    refute matcher.include?("fe80::1%")
  end

  test "IPMatcher accepts bracketed IPv6 addresses and IPv4 addresses with a port" do
    matcher = Internals::IPMatcher.new(["192.0.2.1", "2001:db8::f"])

    assert matcher.include?("192.0.2.1:80")
    assert matcher.include?("[2001:db8::f]")
  end

  test "IPMatcher matches IPv4-mapped IPv6 lookups against IPv4 networks" do
    matcher = Internals::IPMatcher.new(["192.0.2.55", "10.0.0.0/8"])

    [
      "::ffff:192.0.2.55",
      "[::ffff:192.0.2.55]",
      "::FFFF:192.0.2.55",
      "::ffff:c000:237",
      "0:0:0:0:0:ffff:c000:237",
      "::ffff:10.1.2.3"
    ].each do |ip|
      assert matcher.include?(ip), ip
    end

    ["::ffff:198.51.100.1", "::c000:237", "::ffff:0:c000:237", "64:ff9b::c000:237"].each do |ip|
      refute matcher.include?(ip), ip
    end
  end

  test "IPMatcher does not match IPv4 lookups against IPv4-mapped IPv6 networks" do
    matcher = Internals::IPMatcher.new(["::ffff:192.0.2.0/120"])

    refute matcher.include?("192.0.2.1")
    assert matcher.include?("::ffff:192.0.2.1")
  end

  test "IPMatcher preserves embedded IPv4 and mapped address forms" do
    matcher = Internals::IPMatcher.new(["64:ff9b::192.0.2.1", "::ffff:127.0.0.1", "::ffff:0:0:0:0"])

    assert matcher.include?("64:ff9b::c000:201")
    assert matcher.include?("[::ffff:127.0.0.1]")
    assert matcher.include?("::ffff:7f00:1")
    assert matcher.include?("::ffff:0:0:0:0")
    refute matcher.include?("127.0.0.1")
    refute matcher.include?("::ffff:123")
  end

  test "IPMatcher does not normalize shorthand, integer or hexadecimal IPv4 lookups" do
    matcher = Internals::IPMatcher.new(["127.0.0.0/8"])

    assert matcher.include?("127.0.0.1")

    ["127.1", "127.0.1", "2130706433", "0x7f000001", "0x7f.0.0.1"].each do |ip|
      refute matcher.include?(ip), ip
    end
  end

  test "IPMatcher reads leading zeros in IPv4 octets as decimal, not octal" do
    loopback = Internals::IPMatcher.new(["127.0.0.0/8"])
    assert loopback.include?("127.000.000.001")
    refute loopback.include?("0177.0.0.1")

    assert Internals::IPMatcher.new(["177.0.0.0/8"]).include?("0177.0.0.1")

    ten = Internals::IPMatcher.new(["10.0.0.0/8"])
    eight = Internals::IPMatcher.new(["8.0.0.0/8"])
    assert ten.include?("010.0.0.1")
    refute eight.include?("010.0.0.1")
  end

  test "IPMatcher rejects shorthand, integer and hexadecimal IPv4 networks" do
    matcher = Internals::IPMatcher.new(["127.1", "2130706433", "0x7f000001"])

    assert_equal 3, matcher.rejected_count
    refute matcher.include?("127.0.0.1")
  end

  test "IPMatcher rejects malformed networks" do
    matcher = Internals::IPMatcher.new([
      "1.2.3.4.5", "256.0.0.1", "1..2.3", "1.2.3.4/", "127.0.0.1/ 8", "::ffff:1.2.3.4/200"
    ])

    assert_equal 6, matcher.rejected_count
  end

  test "IPMatcher does not include lookups that are not IP addresses" do
    matcher = Internals::IPMatcher.new(["0.0.0.0/0", "::/0"])

    ["not-an-address", "192.168.0.999", "", " ", "1.2.3"].each do |lookup|
      refute matcher.include?(lookup), lookup.inspect
    end
  end

  test "IPMatcher does not include lookups longer than 128 bytes" do
    matcher = Internals::IPMatcher.new(["fe80::/10"])

    # The zone is stripped, so only the length decides these.
    assert matcher.include?("fe80::1%" + "a" * 120)
    refute matcher.include?("fe80::1%" + "a" * 121)
  end

  test "IPMatcher does not include lookups that are not valid UTF-8" do
    matcher = Internals::IPMatcher.new(["fe80::/10"])

    # The zone is stripped, so only the encoding decides these.
    assert matcher.include?("fe80::1%eth0")
    refute matcher.include?("fe80::1%\xC3\x28".b)
  end
end
