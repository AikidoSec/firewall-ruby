# frozen_string_literal: true

require "json"

require_relative "ip_list"
require_relative "writer"
require_relative "../address"

module Aikido::Zen
  module IPLists
    module Data
      # Reads a `Data` file written by `Writer`: many IP lists packed into
      # one physical file.
      #
      # #include? is the fast path: it only checks the merged copy, with no
      # regard for which IP list an address came from. #matching_lists is
      # the rare path -- it only scans the individual IP lists, to recover
      # exactly which one(s) matched, if the merged copy found a match at
      # all.
      class Reader
        Match = Struct.new(:key, :description)

        # @param path [String] a file written by `Writer`
        def initialize(path)
          @file = File.open(path, "rb")

          @file.seek(0)
          toc_length = @file.read(Writer::TOC_LENGTH_SIZE).unpack1("N")
          @toc = JSON.parse(@file.read(toc_length), symbolize_names: true)
          @data_start = Writer::TOC_LENGTH_SIZE + toc_length

          merged = @toc.fetch(:merged)
          @merged = IPList.new(ipv4_reader: reader_for(merged, :ipv4), ipv6_reader: reader_for(merged, :ipv6))
        end

        # @return [Boolean] whether this file has no IP lists in it at all
        def empty?
          @toc.fetch(:ip_lists).empty?
        end

        # The fast path: does this IP appear in this `Data` at all, without
        # regard for which IP list it came from.
        #
        # @param ip [IPAddr, String, nil]
        # @return [Boolean]
        def include?(ip)
          @merged.include?(ip)
        end

        # Which IP list(s) an address matches. Only scans the individual
        # IP lists (the expensive part) if the merged fast path finds a
        # match at all.
        #
        # @param ip [IPAddr, String, nil]
        # @return [Array<Match>] empty if +ip+ doesn't match anything
        def matching_lists(ip)
          return [] unless @merged.include?(ip)

          address = IPLists.parse_ip(ip)
          return [] if address.nil?

          @toc.fetch(:ip_lists).filter_map do |ip_list|
            reader = reader_for(ip_list, address.family)
            Match.new(ip_list.fetch(:key), ip_list.fetch(:description)) if reader.include?(address.to_i)
          end
        end

        def close
          @file.close
        end

        private

        def reader_for(ip_list, family)
          IPList::Reader.new(
            family: family,
            io: @file,
            offset: @data_start + ip_list.fetch(:"#{family}_offset"),
            length: ip_list.fetch(:"#{family}_length")
          )
        end
      end
    end
  end
end
