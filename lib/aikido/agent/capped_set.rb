# frozen_string_literal: true

module Aikido::Agent
  # @api private
  #
  # Provides a FIFO set with a maximum size. Adding an element after the
  # capacity has been reached kicks the oldest element in the set out,
  # while maintaining the uniqueness property of a set (relying on #eql?
  # and #hash).
  class CappedSet
    include Enumerable

    # @return [Integer]
    attr_reader :capacity

    def initialize(capacity)
      raise ArgumentError, "cannot set capacity lower than 1: #{capacity}" if capacity < 1
      @capacity = capacity
      @data = {}
    end

    def <<(element)
      @data[element] = nil
      @data.delete(@data.each_key.first) if @data.size > @capacity
      self
    end
    alias_method :add, :<<
    alias_method :push, :<<

    def each(&b)
      @data.each_key(&b)
    end

    def size
      @data.size
    end

    def empty?
      @data.empty?
    end

    def as_json
      map(&:as_json)
    end
  end
end
