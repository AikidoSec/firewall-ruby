# frozen_string_literal: true

# The current context is stored in an additional Fiber instance variable and
# is accessed through the aikido_current_context accessor methods.

class Fiber
  # @api private
  attr_accessor :aikido_current_context
end

# When a new Thread is instantiated the current context of the Fiber that is
# creating the new Thread is copied into the root Fiber of the new Thread.

# Thread.new calls Thread#initialize, including in subclasses that call super.

class Thread
  # @api private
  alias_method :initialize__internal_for_aikido_zen, :initialize

  def initialize(*args, **kwargs, &blk)
    if blk
      context = Fiber.current.aikido_current_context

      initialize__internal_for_aikido_zen(*args, **kwargs) do |*args, **kwargs|
        Fiber.current.aikido_current_context = context

        blk.call(*args, **kwargs)
      end
    else
      initialize__internal_for_aikido_zen(*args, **kwargs)
    end
  end
end

# Thread.start and Thread.fork do not call Thread#initialize.

class << Thread
  # @api private
  alias_method :start__internal_for_aikido_zen, :start

  def start(*args, **kwargs, &blk)
    if blk
      context = Fiber.current.aikido_current_context

      start__internal_for_aikido_zen(*args, **kwargs) do |*args, **kwargs|
        Fiber.current.aikido_current_context = context

        blk.call(*args, **kwargs)
      end
    else
      start__internal_for_aikido_zen(*args, **kwargs)
    end
  end

  alias_method :fork, :start
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
