# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "aikido/zen/ip_lists/data/writer"
require "aikido/zen/ip_lists/data/reader"

class Aikido::Zen::IPLists::Data::WriterTest < ActiveSupport::TestCase
  FakeIPList = Struct.new(:key, :description, :ipv4_ranges, :ipv6_ranges)

  test "writes a single physical file regardless of how many IP lists there are" do
    ip_lists = Array.new(10) { |i| FakeIPList.new("key#{i}", "description#{i}", [(i * 1000..(i * 1000) + 10)], []) }

    file = Tempfile.new("ip_lists_data_writer_test")
    file.close

    Aikido::Zen::IPLists::Data::Writer.write(file.path, ip_lists)

    assert File.file?(file.path)
    assert_operator File.size(file.path), :>, 0
  ensure
    file.unlink
  end

  test "the written file round-trips through Reader" do
    ip_lists = [FakeIPList.new("key1", "description1", [(10..20)], [])]

    file = Tempfile.new("ip_lists_data_writer_test")
    file.close

    Aikido::Zen::IPLists::Data::Writer.write(file.path, ip_lists)

    reader = Aikido::Zen::IPLists::Data::Reader.new(file.path)
    assert reader.include?(IPAddr.new(15, Socket::AF_INET).to_s)
    reader.close
  ensure
    file.unlink
  end
end
