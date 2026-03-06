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
