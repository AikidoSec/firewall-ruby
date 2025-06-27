# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module DSL
      extend self

      class SafeError < StandardError
      end

      # Safely execute the given block
      #
      # All standard errors are suppressed except `Aikido::Zen::UnderAttackError`s.
      # This ensures that unexpected errors do not interrupt the execution of the
      # original method, while all detected attacks are raised.
      #
      # Error suppression is disabled when `Aikido::Zen.config.debugging?` is true.
      #
      # When an error is wrapped in `SafeError` the original error is reraised.
      #
      # @yield the block to execute
      def safe
        if Aikido::Zen.config.debugging?
          yield
        else
          begin
            yield
          rescue Aikido::Zen::UnderAttackError
            raise
          rescue SafeError => err
            raise err.cause
          rescue
            # empty
          end
        end
      end

      # Unsafely execute the given block
      #
      # Safely wrap standard errors in `SafeError` so that the original error is
      # reraised when rescued in `safe`.
      #
      # @yield the block to execute
      def unsafe
        if Aikido::Zen.config.debugging?
          yield
        else
          begin
            yield
          rescue => err
            raise SafeError, cause: err
          end
        end
      end

      # Define a method `method_name` that unsafely executes the given block before
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute before the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      def unsafe_sink_before(method_name, &block)
        define_method(method_name) do |*args, **kwargs, &blk|
          instance_exec(*args, **kwargs, &block)
          super(*args, **kwargs, &blk)
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
        unsafe_sink_before(method_name) do |*args, **kwargs|
          DSL.safe do
            instance_exec(*args, **kwargs, &block)
          end
        end
      end

      # Define a method `method_name` that unsafely executes the given block after
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute after the original method
      # @yieldparam result [Object] the result returned by the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      def unsafe_sink_after(method_name, &block)
        define_method(method_name) do |*args, **kwargs, &blk|
          result = super(*args, **kwargs, &blk)
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
        unsafe_sink_after(method_name) do |result, *args, **kwargs|
          DSL.safe do
            instance_exec(result, *args, **kwargs, &block)
          end
        end
      end

      # Define a method `method_name` that unsafely executes the given block around
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute around the original method
      # @yieldparam super_call [Proc] the proc that calls the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      def unsafe_sink_around(method_name, &block)
        define_method(method_name) do |*args, **kwargs, &blk|
          result = nil
          super_call = proc do
            result = super(*args, **kwargs, &blk)
          end
          instance_exec(super_call, *args, **kwargs, &block)
          result
        end
      end

      # Define a method `method_name` that safely executes the given block around
      # the original method.
      #
      # @param method_name [Symbol, String] the name of the method to define
      # @yield the block to execute around the original method
      # @yieldparam super_call [Proc] the proc that calls the original method
      # @yieldparam args [Array] the positional arguments passed to the original method
      # @yieldparam kwargs [Hash] the keyword arguments passed to the original method
      #
      # @return [void]
      #
      # @note the block is executed within `safe` to handle errors safely; the original method is executed within `unsafe` to preserve the original behavior
      # @note if the block does not call `super_call`, the original method is called automatically after the block is executed
      def sink_around(method_name, &block)
        unsafe_sink_around(method_name) do |unsafe_super_call, *args, **kwargs|
          super_called = false
          super_call = proc do
            super_called = true
            DSL.unsafe do
              unsafe_super_call.call
            end
          end
          DSL.safe do
            instance_exec(super_call, *args, **kwargs, &block)
          end
          unsafe_super_call.call unless super_called
        end
      end
    end
  end
end
