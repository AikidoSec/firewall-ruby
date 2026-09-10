# frozen_string_literal: true

require "ipaddr"

# Based on https://github.com/demskie/netparser
# MIT License - Copyright (c) 2019 alex

module Aikido::Zen
  class Firewall::IPMatcher
    IPV4_BITS = 32
    IPV6_BITS = 128
    PREFIX_BITS = 8
    PREFIX_MASK = (1 << PREFIX_BITS) - 1
    IPV4_MASK = (1 << IPV4_BITS) - 1
    IPV4_MAPPED_PREFIX = 0xffff
    YJIT_ENABLED = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

    DECIMAL_PREFIX = /\A\s*[+-]?\d/
    HEXADECIMAL = /\A[0-9a-f]{1,4}\z/i
    DECIMAL_NUMBER = /\A[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:e[+-]?\d+)?\z/i
    HEXADECIMAL_NUMBER = /\A0x[0-9a-f]+\z/i
    OCTAL_NUMBER = /\A0o[0-7]+\z/i
    BINARY_NUMBER = /\A0b[01]+\z/i

    def initialize(networks = [])
      ipv4_networks = []
      ipv6_networks = []

      networks.each do |network|
        version = ip_version(network)
        encoded = if version == IPV4_BITS
          parse_ipv4_network(network)
        elsif version == IPV6_BITS
          parse_ipv6_network(network)
        end
        next if encoded.nil?

        ((version == IPV4_BITS) ? ipv4_networks : ipv6_networks) << encoded
      end

      @ipv4_networks = summarize(ipv4_networks, IPV4_BITS).freeze
      @ipv6_networks = summarize(ipv6_networks, IPV6_BITS).freeze
    end

    def include?(network)
      case network
      when String
        include_string?(network)
      when IPAddr
        include_ipaddr?(network)
      when nil
        false
      else
        raise ArgumentError, "no explicit conversion of #{network.class} to IP address"
      end
    end

    def include_with_mapped?(network)
      case network
      when String
        include_string_with_mapped?(network)
      when IPAddr
        include_ipaddr_with_mapped?(network)
      when nil
        false
      else
        raise ArgumentError, "no explicit conversion of #{network.class} to IP address"
      end
    end

    def size
      @ipv4_networks.size + @ipv6_networks.size
    end

    private

    def include_string?(network)
      version = ip_version(network)
      if version == IPV4_BITS
        encoded = if YJIT_ENABLED
          parse_ipv4_address(network) || parse_ipv4_network(network)
        else
          parse_ipv4_network(network)
        end
        !encoded.nil? && include_encoded?(@ipv4_networks, encoded, IPV4_BITS)
      elsif version == IPV6_BITS
        encoded = parse_ipv6_network(network)
        !encoded.nil? && include_encoded?(@ipv6_networks, encoded, IPV6_BITS)
      else
        false
      end
    end

    def include_string_with_mapped?(network)
      version = ip_version(network)
      if version == IPV4_BITS
        encoded = YJIT_ENABLED ? parse_ipv4_address(network) || parse_ipv4_network(network) : parse_ipv4_network(network)
        !encoded.nil? && include_encoded?(@ipv4_networks, encoded, IPV4_BITS)
      elsif version == IPV6_BITS
        encoded = parse_ipv6_network(network)
        return false if encoded.nil?
        return true if include_encoded?(@ipv6_networks, encoded, IPV6_BITS)

        address = encoded >> PREFIX_BITS
        ipv4_mapped?(address) && include_encoded?(
          @ipv4_networks,
          ((address & IPV4_MASK) << PREFIX_BITS) | IPV4_BITS,
          IPV4_BITS
        )
      else
        false
      end
    end

    def include_ipaddr?(network)
      if network.ipv4?
        encoded = (network.to_i << PREFIX_BITS) | network.prefix
        include_encoded?(@ipv4_networks, encoded, IPV4_BITS)
      elsif network.ipv6?
        encoded = (network.to_i << PREFIX_BITS) | network.prefix
        include_encoded?(@ipv6_networks, encoded, IPV6_BITS)
      else
        false
      end
    end

    def include_ipaddr_with_mapped?(network)
      return include_ipaddr?(network) unless network.ipv6?

      encoded = (network.to_i << PREFIX_BITS) | network.prefix
      return true if include_encoded?(@ipv6_networks, encoded, IPV6_BITS)

      network.ipv4_mapped? && include_encoded?(
        @ipv4_networks,
        ((network.to_i & IPV4_MASK) << PREFIX_BITS) | IPV4_BITS,
        IPV4_BITS
      )
    end

    def ip_version(network)
      return unless network.is_a?(String)

      index = 0
      while index < network.length
        character = network.getbyte(index)
        return IPV4_BITS if character == 46
        return IPV6_BITS if character == 58
        index += 1
      end
      nil
    end

    def parse_ipv4_address(address)
      position = 0
      value = 0
      octet = 0
      digits = 0
      separators = 0

      while position < address.length
        character = address.getbyte(position)
        if character.between?(48, 57)
          octet = octet * 10 + character - 48
          return if octet > 255

          digits += 1
        elsif character == 46 && digits.positive? && separators < 3
          value = (value << 8) | octet
          octet = 0
          digits = 0
          separators += 1
        else
          return
        end
        position += 1
      end
      return unless separators == 3 && digits.positive?

      (((value << 8) | octet) << PREFIX_BITS) | IPV4_BITS
    end

    def parse_ipv4_network(network)
      network = trim(network)
      bounds = address_end_and_prefix(network, IPV4_BITS)
      return if bounds.nil?

      address_end = bounds >> PREFIX_BITS
      prefix = bounds & PREFIX_MASK
      address = (address_end == network.length) ? network : network.byteslice(0, address_end)
      parts = address.split(".", -1)
      return unless parts.length == 4

      index = 0
      while index < parts.length
        part = parts[index]
        return unless DECIMAL_PREFIX.match?(part)

        parsed = part.to_i
        return unless parsed.between?(0, 255)

        parts[index] = parsed
        index += 1
      end

      value = (parts[0] << 24) |
        (parts[1] << 16) |
        (parts[2] << 8) |
        parts[3]
      encode(value, prefix, IPV4_BITS)
    end

    def parse_ipv6_network(network)
      network = trim(network)
      bounds = address_end_and_prefix(network, IPV6_BITS)
      return if bounds.nil?

      address_end = bounds >> PREFIX_BITS
      prefix = bounds & PREFIX_MASK
      address = (address_end == network.length) ? network : network.byteslice(0, address_end)
      address = remove_brackets(address)
      return if address.nil? || address.empty?

      zone_index = address.index("%")
      if zone_index
        return if zone_index == address.length - 1

        address = address.byteslice(0, zone_index)
      end
      return encode(0, prefix, IPV6_BITS) if address == "::"

      if !address.include?("::") && !address.include?(".")
        full_address = parse_full_ipv6_address(address)
        return encode(full_address, prefix, IPV6_BITS) unless full_address.nil?
      end

      halves = address.split("::", -1)
      return if halves.empty? || halves.length > 2

      left = parse_ipv6_half(halves[0], false)
      return if left.nil?

      left_units = left & 0xf
      left_value = left >> 4
      if halves.length == 1
        return if left_units > 8

        value = left_value << ((8 - left_units) * 16)
        return encode(value, prefix, IPV6_BITS)
      end

      right = parse_ipv6_half(halves[1], true)
      return if right.nil?

      right_units = right & 0xf
      right_value = right >> 4
      missing_units = 8 - left_units - right_units
      return if missing_units.negative?

      value = (left_value << ((missing_units + right_units) * 16)) | right_value
      encode(value, prefix, IPV6_BITS)
    end

    def trim(value)
      return value if value.empty?

      first = value.getbyte(0)
      last = value.getbyte(value.length - 1)
      (first <= 32 || last <= 32) ? value.strip : value
    end

    def address_end_and_prefix(network, maximum)
      slash = network.index("/")
      return (network.length << PREFIX_BITS) | maximum if slash.nil?
      return if network.index("/", slash + 1)

      position = slash + 1
      prefix = 0
      digits = 0
      while position < network.length
        character = network.getbyte(position)
        break unless character.between?(48, 57)

        prefix = prefix * 10 + character - 48
        return if prefix > maximum

        digits += 1
        position += 1
      end
      return if digits == 0

      (slash << PREFIX_BITS) | prefix
    end

    def remove_brackets(address)
      return address unless address.start_with?("[")

      closing_bracket = address.rindex("]")
      return if closing_bracket.nil?

      address.byteslice(1, closing_bracket - 1)
    end

    def parse_full_ipv6_address(address)
      parts = address.split(":", -1)
      return unless parts.length == 8

      value = 0
      index = 0
      while index < parts.length
        part = parts[index]
        return unless HEXADECIMAL.match?(part)

        value = (value << 16) | part.to_i(16)
        index += 1
      end
      value
    end

    def parse_ipv6_half(half, remove_port)
      return 0 if half.empty?

      value = 0
      units = 0
      parts = half.split(":", -1)
      index = 0
      while index < parts.length
        parsed = parse_ipv6_component(parts[index], remove_port && index == parts.length - 1)
        return if parsed.nil?

        part_units = parsed & 0x3
        units += part_units
        return if units > 8

        value = (value << (part_units * 16)) | (parsed >> 2)
        index += 1
      end
      (value << 4) | units
    end

    def parse_ipv6_component(component, remove_port)
      if component.count(".") == 3
        ipv4 = parse_embedded_ipv4(component)
        return if ipv4.nil?

        return (ipv4 << 2) | 2
      end

      component = remove_port_info(component) if remove_port
      return unless HEXADECIMAL.match?(component)

      (component.to_i(16) << 2) | 1
    end

    def parse_embedded_ipv4(address)
      parts = address.split(".", -1)
      return unless parts.length == 4

      value = 0
      index = 0
      while index < parts.length
        number = parse_number(parts[index])
        return if number.nil? || !number.between?(0, 255)

        value = (value << 8) | number
        index += 1
      end
      value
    end

    def parse_number(value)
      value = value.strip
      return 0 if value.empty?
      return value.to_i(16) if HEXADECIMAL_NUMBER.match?(value)
      return value.to_i(8) if OCTAL_NUMBER.match?(value)
      return value.to_i(2) if BINARY_NUMBER.match?(value)
      return unless DECIMAL_NUMBER.match?(value)

      number = value.to_f
      number.to_i if number.finite? && number == number.to_i
    end

    def remove_port_info(value)
      index = 0
      while index < value.length
        character = value.getbyte(index)
        return value.byteslice(0, index).rstrip if character == 35 || character == 112 || character == 46

        index += 1
      end
      value
    end

    def encode(address, prefix, bits)
      host_bits = bits - prefix
      address = (host_bits == bits) ? 0 : (address >> host_bits) << host_bits
      (address << PREFIX_BITS) | prefix
    end

    def summarize(networks, bits)
      networks.sort!
      summarized = []

      networks.each do |network|
        next if !summarized.empty? && contains?(summarized[-1], network, bits)

        summarized << network
        while summarized.length >= 2
          first = summarized[-2]
          second = summarized[-1]
          prefix = first & PREFIX_MASK
          break if prefix.zero? || prefix != (second & PREFIX_MASK)

          first_address = first >> PREFIX_BITS
          network_size = 1 << (bits - prefix)
          break unless (first_address & ~(network_size * 2 - 1)) == first_address
          break unless first_address + network_size == second >> PREFIX_BITS

          summarized[-2] = (first_address << PREFIX_BITS) | (prefix - 1)
          summarized.pop
        end
      end

      summarized
    end

    def include_encoded?(networks, candidate, bits)
      index = upper_bound(networks, candidate) - 1
      index >= 0 && contains?(networks[index], candidate, bits)
    end

    def upper_bound(networks, candidate)
      left = 0
      right = networks.length
      while left < right
        middle = (left + right) / 2
        if networks[middle] <= candidate
          left = middle + 1
        else
          right = middle
        end
      end
      left
    end

    def contains?(network, candidate, bits)
      prefix = network & PREFIX_MASK
      candidate_prefix = candidate & PREFIX_MASK
      return true if prefix.zero?
      return false if prefix > candidate_prefix

      shift = PREFIX_BITS + bits - prefix
      (network >> shift) == (candidate >> shift)
    end

    def ipv4_mapped?(address)
      address >> IPV4_BITS == IPV4_MAPPED_PREFIX
    end
  end
end
