# frozen_string_literal: true

module Aikido::Zen
  # @!visibility private
  #
  # Provides the synchronization part of Concurrent's LockableObject, but allows
  # objects to take keyword arguments as well.
  #
  # NOTE: This is meant to be prepennded.
  module Synchronizable
    def initialize(*, **)
      @__lock__ = ::Mutex.new
      super
    end

    def synchronize
      if @__lock__.owned?
        yield
      else
        @__lock__.synchronize { yield }
      end
    end
  end
end
