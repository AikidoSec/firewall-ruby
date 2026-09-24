# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "aikido/zen/ip_lists/writer"
require "aikido/zen/ip_lists"

class Aikido::Zen::IPLists::WriterTest < ActiveSupport::TestCase
  def write(ip_lists_data)
    file = Tempfile.new("ip_lists_writer_test")
    file.close

    Aikido::Zen::IPLists::Writer.new(file.path).write(ip_lists_data)

    file
  end

  def range(cidr)
    ip = IPAddr.new(cidr)
    span = ip.to_range
    (span.begin.to_i..span.end.to_i)
  end

  test "#write writes just the file header for an empty array" do
    file = write([])

    assert File.file?(file.path)
    assert_equal Aikido::Zen::IPLists::FILE_HEADER_SIZE, File.size(file.path)
  ensure
    file.unlink
  end

  test "#write leaves no temp file behind" do
    file = write([{ipv4_ranges: [range("10.0.0.0/24")], ipv6_ranges: [], data: "data"}])

    refute File.exist?("#{file.path}.tmp")
  ensure
    file.unlink
  end

  test "#write writes the exact bytes for every IP list" do
    ip_lists_data = Array.new(10) { |i| {ipv4_ranges: [range("10.0.#{i}.0/24")], ipv6_ranges: [], data: "data#{i}"} }

    file = write(ip_lists_data)

    expected_size = Aikido::Zen::IPLists::FILE_HEADER_SIZE + ip_lists_data.sum do |ip_list_data|
      ipv4_size = Aikido::Zen::IPLists::COUNT_SIZE + (ip_list_data[:ipv4_ranges].size * Aikido::Zen::IPLists::ADDRESS_SIZES.fetch(:ipv4) * 2)
      ipv6_size = Aikido::Zen::IPLists::COUNT_SIZE + (ip_list_data[:ipv6_ranges].size * Aikido::Zen::IPLists::ADDRESS_SIZES.fetch(:ipv6) * 2)
      data_size = Aikido::Zen::IPLists::COUNT_SIZE + ip_list_data[:data].bytesize

      ipv4_size + ipv6_size + data_size
    end

    assert File.file?(file.path)
    assert_equal expected_size, File.size(file.path)
  ensure
    file.unlink
  end

  test "#write round-trips through IPLists.new, in order, data included" do
    ip_lists_data = [
      {ipv4_ranges: [range("10.0.0.0/24")], ipv6_ranges: [], data: "first"},
      {ipv4_ranges: [range("10.0.1.0/24")], ipv6_ranges: [], data: "second"}
    ]

    file = write(ip_lists_data)
    bundle = Aikido::Zen::IPLists.new(file.path)

    assert_equal 2, bundle.size
    assert bundle[0].include?("10.0.0.1")
    refute bundle[0].include?("10.0.1.1")
    assert_equal "first", bundle[0].data

    assert bundle[1].include?("10.0.1.1")
    assert_equal "second", bundle[1].data

    bundle.close
  ensure
    file.unlink
  end

  test "#write round-trips nil data as an empty string" do
    file = write([{ipv4_ranges: [], ipv6_ranges: [], data: nil}])
    bundle = Aikido::Zen::IPLists.new(file.path)

    assert_equal "", bundle[0].data

    bundle.close
  ensure
    file.unlink
  end
end
