# frozen_string_literal: true

require_relative "ip_lists/address"
require_relative "ip_lists/format"
require_relative "ip_lists/ip_list"
require_relative "ip_lists/writer"
require_relative "ip_lists/reader"

module Aikido::Zen
  class IPLists
    include Enumerable

    def self.write(path, ip_lists_data)
      Writer.new(path).write(ip_lists_data)
    end

    # @param path [String]
    # @raise [Errno::ENOENT] if `path` does not exist
    # @raise [Aikido::Zen::IPLists::FormatError] if `path` is not a valid IP lists file
    def initialize(path)
      @reader = Reader.new(path)
      @ip_lists = @reader.ip_lists
    end

    # @yieldparam ip_list [Aikido::Zen::IPLists::IPList]
    # @return [void]
    def each(&block)
      @ip_lists.each(&block)
    end

    def empty?
      @ip_lists.empty?
    end

    # @param index [Integer]
    # @return [Aikido::Zen::IPLists::IPList, nil]
    def [](index)
      @ip_lists[index]
    end

    def size
      @ip_lists.size
    end

    def close
      @reader.close
    end
  end
end
