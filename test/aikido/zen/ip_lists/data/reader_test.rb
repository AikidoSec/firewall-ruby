# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "aikido/zen/ip_lists/data/reader"
require "aikido/zen/ip_lists/data/writer"

class Aikido::Zen::IPLists::Data::ReaderTest < ActiveSupport::TestCase
  FakeIPList = Struct.new(:key, :description, :ipv4_ranges, :ipv6_ranges)

  def with_reader(ip_lists)
    file = Tempfile.new("ip_lists_data_reader_test")
    file.close

    Aikido::Zen::IPLists::Data::Writer.write(file.path, ip_lists)
    reader = Aikido::Zen::IPLists::Data::Reader.new(file.path)

    yield reader
  ensure
    reader&.close
    file.unlink
  end

  test "#empty? is true when there are no IP lists" do
    with_reader([]) do |reader|
      assert reader.empty?
    end
  end

  test "#empty? is false when there's at least one IP list" do
    with_reader([FakeIPList.new("key1", "description1", [(10..20)], [])]) do |reader|
      refute reader.empty?
    end
  end

  test "#include? is true for an ip covered by any IP list" do
    ip_lists = [
      FakeIPList.new("key1", "description1", [(10..20)], []),
      FakeIPList.new("key2", "description2", [(1000..2000)], [])
    ]

    with_reader(ip_lists) do |reader|
      assert reader.include?(IPAddr.new(15, Socket::AF_INET).to_s)
      assert reader.include?(IPAddr.new(1500, Socket::AF_INET).to_s)
      refute reader.include?(IPAddr.new(500, Socket::AF_INET).to_s)
    end
  end

  test "#include? checks the ipv6 data for ipv6 addresses" do
    start_ip = 0x2001_0db8_0000_0000_0000_0000_0000_0000
    end_ip = 0x2001_0db8_ffff_ffff_ffff_ffff_ffff_ffff

    ip_lists = [FakeIPList.new("key1", "description1", [], [(start_ip..end_ip)])]

    with_reader(ip_lists) do |reader|
      assert reader.include?(IPAddr.new(start_ip + 1, Socket::AF_INET6).to_s)
      refute reader.include?(IPAddr.new(start_ip - 1, Socket::AF_INET6).to_s)
    end
  end

  test "#include? is false for nil and for unparseable input" do
    with_reader([FakeIPList.new("key1", "description1", [(10..20)], [])]) do |reader|
      refute reader.include?(nil)
      refute reader.include?("not an ip address")
    end
  end

  test "#matching_lists is empty when nothing matches" do
    ip_lists = [FakeIPList.new("key1", "description1", [(10..20)], [])]

    with_reader(ip_lists) do |reader|
      assert_equal [], reader.matching_lists(IPAddr.new(500, Socket::AF_INET).to_s)
      assert_equal [], reader.matching_lists(nil)
      assert_equal [], reader.matching_lists("not an ip address")
    end
  end

  test "#matching_lists identifies the one IP list an ip came from" do
    ip_lists = [
      FakeIPList.new("key1", "description1", [(10..20)], []),
      FakeIPList.new("key2", "description2", [(1000..2000)], [])
    ]

    with_reader(ip_lists) do |reader|
      matches = reader.matching_lists(IPAddr.new(15, Socket::AF_INET).to_s)

      assert_equal 1, matches.size
      assert_equal "key1", matches.first.key
      assert_equal "description1", matches.first.description
    end
  end

  test "#matching_lists identifies every IP list when ranges overlap" do
    ip_lists = [
      FakeIPList.new("key1", "description1", [(10..50)], []),
      FakeIPList.new("key2", "description2", [(30..70)], []),
      FakeIPList.new("key3", "description3", [(1000..2000)], [])
    ]

    with_reader(ip_lists) do |reader|
      matches = reader.matching_lists(IPAddr.new(40, Socket::AF_INET).to_s)

      assert_equal %w[key1 key2], matches.map(&:key).sort
    end
  end

  test "an ip covered by an unattributed gap in the merged copy still resolves correctly" do
    # key1 and key2 overlap and merge into one copy covering 10..70; 55 is
    # only actually covered by key2, not key1 -- the fast path (merged)
    # should say yes, and the fallback should correctly say only key2, not
    # key1.
    ip_lists = [
      FakeIPList.new("key1", "description1", [(10..50)], []),
      FakeIPList.new("key2", "description2", [(45..70)], [])
    ]

    with_reader(ip_lists) do |reader|
      assert reader.include?(IPAddr.new(60, Socket::AF_INET).to_s)

      matches = reader.matching_lists(IPAddr.new(60, Socket::AF_INET).to_s)
      assert_equal ["key2"], matches.map(&:key)
    end
  end
end
