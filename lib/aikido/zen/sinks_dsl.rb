# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module DSL
      extend self

      # In the context of `Aikido::Zen::Sinks::DSL`, the terms safe and presafe
      # are defined as follows:
      #
      # safe: the desired state for a sink, particularly with respect to rescue.
      #
      # A sink is considered safe when unintended errors in the sink are handled,
      # and-so are prevented from disrupting the operation of the original method
      # (by raising unintended errors).
      #
      # presafe: the default state of a sink, particularly with respect to rescue.
      #
      # A sink is in the presafe state before and while unintended errors in the
      # sink are not handled.
      #
      # Sink methods (like all methods) are in the presafe state when defined and
      # become safe when unexpected errors cannot cause harm. The `safe` method
      # is used to establish a safe state for the duration of the block executed.
      # It is sometimes useful to be able to reestablish the presafe safe while
      # inside a `safe` block; the `presafe` method allows this.
      #
      # Methods that contain the term presafe in their name should be used with
      # appropriate care and understanding.
      #
      # IMPORTANT: All sinks should be safe!
      #
      # While this DSL proves useful for defining safe sink methods that follow
      # common patterns, there are exceptions. It is always possible to define
      # sink methods without using this DSL, but this should only be done when
      # absolutely necessary. The sink methods defined using this DSL are safe,
      # unless explicitly declared presafe.
      #
      # IMPORTANT: No sinks should be presafe in production!
      #
      # We are all responsible for ensuring that the sinks we implement are safe
      # for production use. This DSL is only here to assist, by taking care of
      # delicate edge cases and reducing the space for errors.
      #
      # When writing sink methods manually, some principles should be considered,
      # to ensure safety for production:
      #
      # 1. Sink methods should ensure that the original method is always called,
      # passing all parameters (positional, keyword, and block) exactly as they
      # were passed to the original method, and return the result returned by
      # the original method exactly as it was returned by the original method.
      # (Unless intervention is required.)
      #
      # 2. Sink methods should not predict the signature of the original method,
      # and-so restrict it from varying. The original method implementation is
      # the sole and ultimate reference for its own behavior. We are observers
      # (unless intervention is required).
      #
      # 3. Unexpected errors that are encountered in sink methods should not be
      # capable of interfering with or preventing the normal operation of the
      # original method. This includes but is not limited to exceptions that
      # that may be raised when the sink method is called. Safe sink methods
      # should return control to their caller (unless intervention is required).
      #
      # These are the guidelines adhered to by the `Aikido::Zen::Sinks::DSL`.

      # The error with an original error as its cause to re-raise in `safe`.
      class PresafeError < StandardError
      end

      # Safely execute the given block
      #
      # All standard errors are suppressed except `Aikido::Zen::UnderAttackError`s.
      # This ensures that unexpected errors do not interrupt the execution of the
      # original method, while all detected attacks are raised.
      #
      # When an error is wrapped in `PresafeError` the original error is reraised.
      #
      # @yield the block to execute
      def safe
        yield
      rescue Aikido::Zen::UnderAttackError
        raise
      rescue PresafeError => err
        raise err.cause
      rescue => err
        Aikido::Zen.config.logger.debug("[safe] #{err.class}: #{err.message}")
      end

      # Presafely execute the given block
      #
      # Safely wrap standard errors in `PresafeError` so that the original error is
      # reraised when rescued in `safe`.
      #
      # @yield the block to execute
      def presafe
        yield
      rescue => err
        raise PresafeError, cause: err
      end

      # Define a method `method_name` that presafely executes the given block before
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute before the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      def presafe_sink_before(method_name, &block)
        original = instance_method(method_name)

        define_method(method_name) do |*args, **kwargs, &blk|
          instance_exec(*args, **kwargs, &block)
          original.bind_call(self, *args, **kwargs, &blk)
        end
      end

      # Define a method `method_name` that safely executes the given block before
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute before the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      #
      # @note the block is executed within `safe` to handle errors safely; the original method is executed outside of `safe` to preserve the original behavior
      def sink_before(method_name, &block)
        presafe_sink_before(method_name) do |*args, **kwargs|
          DSL.safe do
            instance_exec(*args, **kwargs, &block)
          end
        end
      end

      # Define a method `method_name` that presafely executes the given block after
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute after the original method
      # @yieldparam result [Object] the result returned by the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      def presafe_sink_after(method_name, &block)
        original = instance_method(method_name)

        define_method(method_name) do |*args, **kwargs, &blk|
          result = original.bind_call(self, *args, **kwargs, &blk)
          instance_exec(result, *args, **kwargs, &block)
          result
        end
      end

      # Define a method `method_name` that safely executes the given block after
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute after the original method
      # @yieldparam result [Object] the result returned by the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      #
      # @note the block is executed within `safe` to handle errors safely; the original method is executed outside of `safe` to preserve the original behavior
      def sink_after(method_name, &block)
        presafe_sink_after(method_name) do |result, *args, **kwargs|
          DSL.safe do
            instance_exec(result, *args, **kwargs, &block)
          end
        end
      end

      # Define a method `method_name` that presafely executes the given block around
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute around the original method
      # @yieldparam original_call [Proc] the proc that calls the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      def presafe_sink_around(method_name, &block)
        original = instance_method(method_name)

        define_method(method_name) do |*args, **kwargs, &blk|
          result = nil
          original_call = proc do
            result = original.bind_call(self, *args, **kwargs, &blk)
          end
          instance_exec(original_call, *args, **kwargs, &block)
          result
        end
      end

      # Define a method `method_name` that safely executes the given block around
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute around the original method
      # @yieldparam original_call [Proc] the proc that calls the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      #
      # @note the block is executed within `safe` to handle errors safely; the original method is executed within `presafe` to preserve the original behavior
      # @note if the block does not call `original_call`, the original method is called automatically after the block is executed
      def sink_around(method_name, &block)
        presafe_sink_around(method_name) do |presafe_original_call, *args, **kwargs|
          original_called = false
          original_call = proc do
            original_called = true
            DSL.presafe do
              presafe_original_call.call
            end
          end
          DSL.safe do
            instance_exec(original_call, *args, **kwargs, &block)
          end
          presafe_original_call.call unless original_called
        end
      end
    end
  end
end
