# frozen_string_literal: true

require "test_helper"
require "aikido/zen/ip_lists/ip_list/writer"

class Aikido::Zen::IPLists::IPList::WriterTest < ActiveSupport::TestCase
  test "#initialize raises for an unknown family" do
    assert_raises(ArgumentError) { Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv5) }
  end

  test "#write writes just a count for an empty ipv4 list" do
    io = StringIO.new
    Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv4).write(io, [])

    bytes = io.string
    assert_equal 8, bytes.bytesize
    assert_equal 0, bytes.unpack1("Q>")
  end

  test "#write writes just a count for an empty ipv6 list" do
    io = StringIO.new
    Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv6).write(io, [])

    bytes = io.string
    assert_equal 8, bytes.bytesize
    assert_equal 0, bytes.unpack1("Q>")
  end

  test "#write writes ipv4 ranges as 8-byte big-endian records" do
    ranges = [(0..255), (2**32 - 10..2**32 - 1)]

    io = StringIO.new
    Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv4).write(io, ranges)

    bytes = io.string
    assert_equal 8 + (ranges.size * 8), bytes.bytesize
    assert_equal ranges.size, bytes.unpack1("Q>")

    records = bytes.byteslice(8..).unpack("N*")
    assert_equal [0, 255, 2**32 - 10, 2**32 - 1], records
  end

  test "#write sorts ranges by start before writing, regardless of input order" do
    ranges = [(100..200), (2**32 - 10..2**32 - 1), (0..50)]

    io = StringIO.new
    Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv4).write(io, ranges)

    records = io.string.byteslice(8..).unpack("N*")
    assert_equal [0, 50, 100, 200, 2**32 - 10, 2**32 - 1], records
  end

  test "#write writes ipv6 ranges as 32-byte big-endian records" do
    start_ip = 0x2001_0db8_0000_0000_0000_0000_0000_0000
    end_ip = 0x2001_0db8_ffff_ffff_ffff_ffff_ffff_ffff

    io = StringIO.new
    Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv6).write(io, [(start_ip..end_ip)])

    bytes = io.string
    assert_equal 8 + 32, bytes.bytesize

    start_hi, start_lo, end_hi, end_lo = bytes.byteslice(8..).unpack("Q>*")
    assert_equal start_ip, (start_hi << 64) | start_lo
    assert_equal end_ip, (end_hi << 64) | end_lo
  end

  test "#write writes ipv4 ranges at the given offset" do
    io = StringIO.new(+"\x00" * 10, "r+")
    Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv4).write(io, [(0..255)], offset: 10)

    assert_equal 10 + 8 + 8, io.string.bytesize
    assert_equal "\x00" * 10, io.string.byteslice(0, 10)
    assert_equal 1, io.string.byteslice(10..).unpack1("Q>")
  end

  test "#write writes ipv6 ranges at the given offset" do
    io = StringIO.new(+"\x00" * 10, "r+")
    start_ip = 0x2001_0db8_0000_0000_0000_0000_0000_0000
    end_ip = 0x2001_0db8_0000_0000_0000_0000_0000_00ff

    Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv6).write(io, [(start_ip..end_ip)], offset: 10)

    assert_equal 10 + 8 + 32, io.string.bytesize
    assert_equal "\x00" * 10, io.string.byteslice(0, 10)
    assert_equal 1, io.string.byteslice(10..).unpack1("Q>")
  end

  test "#write returns the io it was given" do
    io = StringIO.new
    result = Aikido::Zen::IPLists::IPList::Writer.new(family: :ipv4).write(io, [])

    assert_same io, result
  end
end
