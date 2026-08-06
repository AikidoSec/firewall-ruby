# frozen_string_literal: true

module Aikido::Zen
  module IPLists
    module Data
      # Shared constants describing the on-disk binary format used by
      # `IPList::Writer` and `IPList::Reader`.
      MAGIC = "AKPL"
      VERSION = 1

      FAMILY_CODES = {ipv4: 4, ipv6: 6}.freeze

      HEADER_SIZE = 16
      RECORD_SIZES = {ipv4: 8, ipv6: 32}.freeze
    end
  end
end
