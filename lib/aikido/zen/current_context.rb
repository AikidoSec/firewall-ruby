# frozen_string_literal: true

# The current context is stored in an additional Fiber instance variable and
# is though the aikido_current_context accessor methods.

class Fiber
  # @api private
  attr_accessor :aikido_current_context
end

# When a new Fiber is instantiated the current context of the Fiber that is
# creating the new Fiber is copied into the new Fiber.

class << Fiber
  # @api private
  alias_method :new__internal_for_aikido_zen, :new

  def new(*args, **kwargs, &blk)
    context = Fiber.current.aikido_current_context

    new__internal_for_aikido_zen(*args, **kwargs) do |*args|
      Fiber.current.aikido_current_context = context

      blk.call(*args)
    end
  end
end

module Aikido::Zen
  # Mirror of the Fiber-local context above, used only as a fallback when that
  # one is empty.
  #
  # ActionController::Live runs the action in its own thread, where the
  # Fiber-local is gone. Rails copies the IsolatedExecutionState into that
  # thread for us (ActiveSupport::IsolatedExecutionState#share_with), so this is
  # what carries the context across the hop. No-op when ActiveSupport is absent.
  #
  # @api private
  module SharedContext
    KEY = :aikido_current_context

    def self.available?
      defined?(ActiveSupport::IsolatedExecutionState) ? true : false
    end

    def self.get
      ActiveSupport::IsolatedExecutionState[KEY] if available?
    end

    def self.set(context)
      ActiveSupport::IsolatedExecutionState[KEY] = context if available?
    end
  end
end
