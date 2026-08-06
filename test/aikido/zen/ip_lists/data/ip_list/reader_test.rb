# frozen_string_literal: true

require "test_helper"
require "aikido/zen/ip_lists/data/ip_list/reader"
require "aikido/zen/ip_lists/data/ip_list/writer"

class Aikido::Zen::IPLists::Data::IPList::ReaderTest < ActiveSupport::TestCase
  def io_with_ranges(family:, ranges:)
    io = StringIO.new(+"", "r+")
    io.set_encoding(Encoding::BINARY)
    Aikido::Zen::IPLists::Data::IPList::Writer.new(family: family).write(io, ranges)
    io
  end

  def io_with_bytes(bytes)
    StringIO.new(bytes)
  end

  test "raises for an unknown family" do
    assert_raises(ArgumentError) do
      Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv5, io: io_with_bytes(""))
    end
  end

  test "#include? is false for an empty ipv4 list" do
    reader = Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io_with_ranges(family: :ipv4, ranges: []))

    refute reader.include?(0)
    refute reader.include?(2**32 - 1)
  end

  test "#include? matches ipv4 ranges, including boundaries and gaps" do
    ranges = [(10..20), (100..200), (2**32 - 5..2**32 - 1)]
    reader = Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io_with_ranges(family: :ipv4, ranges: ranges))

    [10, 15, 20, 100, 150, 200, 2**32 - 5, 2**32 - 1].each do |ip|
      assert reader.include?(ip), "expected #{ip} to be included"
    end

    [0, 9, 21, 99, 201, 2**32 - 6].each do |ip|
      refute reader.include?(ip), "expected #{ip} not to be included"
    end
  end

  test "#include? matches an ipv6 range spanning the 64-bit boundary" do
    start_ip = 0x2001_0db8_0000_0000_0000_0000_0000_0000
    end_ip = 0x2001_0db8_ffff_ffff_ffff_ffff_ffff_ffff

    reader = Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv6, io: io_with_ranges(family: :ipv6, ranges: [(start_ip..end_ip)]))

    assert reader.include?(start_ip)
    assert reader.include?(end_ip)
    assert reader.include?(start_ip + 1)
    refute reader.include?(start_ip - 1)
    refute reader.include?(end_ip + 1)
  end

  test "raises FormatError for data with the wrong magic" do
    assert_raises(Aikido::Zen::IPLists::Data::IPList::Reader::FormatError) do
      Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io_with_bytes(["NOPE", 1, 4, 0, 0].pack("a4CCnQ>")))
    end
  end

  test "raises FormatError for an unsupported format version" do
    assert_raises(Aikido::Zen::IPLists::Data::IPList::Reader::FormatError) do
      Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io_with_bytes(["AKPL", 2, 4, 0, 0].pack("a4CCnQ>")))
    end
  end

  test "raises FormatError when the data's family doesn't match the reader's" do
    assert_raises(Aikido::Zen::IPLists::Data::IPList::Reader::FormatError) do
      Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io_with_ranges(family: :ipv6, ranges: []))
    end
  end

  test "raises FormatError when the record count doesn't match the available size" do
    # header claims 5 records, but there are none in the data
    assert_raises(Aikido::Zen::IPLists::Data::IPList::Reader::FormatError) do
      Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io_with_bytes(["AKPL", 1, 4, 0, 5].pack("a4CCnQ>")))
    end
  end

  test "raises FormatError for data too small to contain a header" do
    assert_raises(Aikido::Zen::IPLists::Data::IPList::Reader::FormatError) do
      Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io_with_bytes("short"))
    end
  end

  test "many readers can share one underlying IO, each at its own offset, without interfering with each other" do
    io = StringIO.new(+"", "r+")
    io.set_encoding(Encoding::BINARY)

    Aikido::Zen::IPLists::Data::IPList::Writer.new(family: :ipv4).write(io, [(10..20)])
    blob_a_size = io.string.bytesize

    Aikido::Zen::IPLists::Data::IPList::Writer.new(family: :ipv4).write(io, [(1000..2000)], offset: blob_a_size)
    blob_b_size = io.string.bytesize - blob_a_size

    reader_a = Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io, offset: 0, length: blob_a_size)
    reader_b = Aikido::Zen::IPLists::Data::IPList::Reader.new(family: :ipv4, io: io, offset: blob_a_size, length: blob_b_size)

    assert reader_a.include?(15)
    refute reader_a.include?(1500)

    assert reader_b.include?(1500)
    refute reader_b.include?(15)
  end
end
