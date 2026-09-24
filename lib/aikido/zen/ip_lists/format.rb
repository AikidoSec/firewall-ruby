# frozen_string_literal: true

module Aikido::Zen
  class IPLists
    # Raised when a file is not a valid IP lists file.
    FormatError = Class.new(StandardError)

    MAGIC = "IPLS"
    VERSION = 1
    FILE_HEADER_SIZE = 5 # magic (4) + version (1)

    # Bytes per ipv4/ipv6 address.
    ADDRESS_SIZES = {ipv4: 4, ipv6: 16}.freeze

    # Bytes per count/length prefix (uint64 BE).
    COUNT_SIZE = 8
  end
end
