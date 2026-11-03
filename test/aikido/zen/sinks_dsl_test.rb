# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::SinksDSLTest < ActiveSupport::TestCase
  class MyClass
    def self.original_for_before(a, b = 2, c: 3)
      "result of MyClass.original_for_before(#{a}, b = #{b}, c: #{c})"
    end

    def self.original_for_after
      "result of MyClass.original_for_after"
    end

    def self.original_for_around(a, b = 2, c: 3)
      "result of MyClass.original_for_around(#{a}, b = #{b}, c: #{c})"
    end

    def original_for_before
      "result of MyClass#original_for_before"
    end

    def original_for_after(a, b = 2, c: 3)
      "result of MyClass#original_for_after(#{a}, b = #{b}, c: #{c})"
    end

    def original_for_around
      "result of MyClass#original_for_around"
    end

    def original_for_presafe_before
      "result of MyClass#original_for_before"
    end

    def original_for_presafe_after
      "result of MyClass#original_for_after"
    end

    def original_for_presafe_around
      "result of MyClass#original_for_around"
    end
  end

  MyClass.singleton_class.class_eval do
    extend Aikido::Zen::Sinks::DSL

    attr_reader :sink_before_original_called
    attr_reader :sink_before_original_argument_error

    attr_reader :sink_after_original_called

    attr_reader :sink_around_original_called
    attr_reader :sink_around_original_argument_error
    attr_reader :sink_around_original_result_error
    attr_reader :sink_around_original_before_original_call
    attr_reader :sink_around_original_after_original_call

    sink_before :original_for_before do |a, b, c:|
      @sink_before_original_called = true

      @sink_before_original_argument_error = a != 4 || b != 5 || c != 6
    end

    sink_after :original_for_after do
      @sink_after_original_called = true

      # Simulate error in sink, should NOT escape sink.
      raise StandardError
    end

    sink_around :original_for_around do |original_call, a, b, c:|
      @sink_around_original_called = true

      @sink_around_original_argument_error = a != 4 || b != 5 || c != 6

      @sink_around_original_before_original_call = true

      result = original_call.call

      @sink_around_original_result_error = result != "result of MyClass.original_for_around(4, b = 5, c: 6)"

      @sink_around_original_after_original_call = true
    end
  end

  MyClass.class_eval do
    extend Aikido::Zen::Sinks::DSL

    attr_reader :sink_before_original_called

    attr_reader :sink_after_original_called
    attr_reader :sink_after_original_argument_error

    attr_reader :sink_around_original_called
    attr_reader :sink_around_original_before_original_call
    attr_reader :sink_around_original_after_original_call

    sink_before :original_for_before do
      @sink_before_original_called = true

      # Simulate error in sink, should NOT escape sink.
      raise StandardError
    end

    sink_after :original_for_after do |a, b, c:|
      @sink_after_original_called = true

      @sink_after_original_argument_error = a != 4 || b != 5 || c != 6
    end

    sink_around :original_for_around do |original_call|
      @sink_around_original_called = true

      @sink_around_original_before_original_call = true

      # Simulate error in sink, should NOT escape sink.
      raise StandardError

      # rubocop:disable Lint/UnreachableCode

      original_call.call

      @sink_around_original_after_original_call = true

      # rubocop:enable Lint/UnreachableCode
    end

    presafe_sink_before :original_for_presafe_before do
      # Simulate error in sink, should escape sink.
      raise StandardError
    end

    presafe_sink_after :original_for_presafe_after do
      # Simulate error in sink, should escape sink.
      raise StandardError
    end

    presafe_sink_around :original_for_presafe_around do
      # Simulate error in sink, should escape sink.
      raise StandardError
    end
  end

  test "sink before class method" do
    assert_nil MyClass.sink_before_original_called
    assert_nil MyClass.sink_before_original_argument_error

    assert_equal "result of MyClass.original_for_before(4, b = 5, c: 6)", MyClass.original_for_before(4, 5, c: 6)

    refute_nil MyClass.sink_before_original_called
    assert_equal false, MyClass.sink_before_original_argument_error
  end

  test "sink after class method" do
    assert_nil MyClass.sink_after_original_called

    assert_equal "result of MyClass.original_for_after", MyClass.original_for_after

    refute_nil MyClass.sink_after_original_called
  end

  test "sink around class method" do
    assert_nil MyClass.sink_around_original_called
    assert_nil MyClass.sink_around_original_argument_error
    assert_nil MyClass.sink_around_original_result_error
    assert_nil MyClass.sink_around_original_before_original_call
    assert_nil MyClass.sink_around_original_after_original_call

    assert_equal "result of MyClass.original_for_around(4, b = 5, c: 6)", MyClass.original_for_around(4, 5, c: 6)

    refute_nil MyClass.sink_around_original_called
    assert_equal false, MyClass.sink_around_original_argument_error
    assert_equal false, MyClass.sink_around_original_result_error
    refute_nil MyClass.sink_around_original_before_original_call
    refute_nil MyClass.sink_around_original_after_original_call
  end

  test "sink before instance method" do
    instance = MyClass.new

    assert_nil instance.sink_before_original_called

    assert_equal "result of MyClass#original_for_before", instance.original_for_before

    refute_nil instance.sink_before_original_called
  end

  test "sink after instance method" do
    instance = MyClass.new

    assert_nil instance.sink_after_original_called
    assert_nil instance.sink_after_original_argument_error

    assert_equal "result of MyClass#original_for_after(4, b = 5, c: 6)", instance.original_for_after(4, 5, c: 6)

    refute_nil instance.sink_after_original_called
    refute_equal false, instance.sink_after_original_argument_error
  end

  test "sink around instance method" do
    instance = MyClass.new

    assert_nil instance.sink_around_original_called
    assert_nil instance.sink_around_original_before_original_call
    assert_nil instance.sink_around_original_after_original_call

    assert_equal "result of MyClass#original_for_around", instance.original_for_around

    refute_nil instance.sink_around_original_called
    refute_nil instance.sink_around_original_before_original_call
    assert_nil instance.sink_around_original_after_original_call
  end

  test "sink before undefined class method" do
    refute_respond_to MyClass, :undefined_original_for_before

    assert_silent do
      MyClass.singleton_class.class_eval do
        sink_before :undefined_original_for_before do
          # empty
        end
      end
    end

    refute_respond_to MyClass, :undefined_original_for_before
  end

  test "sink after undefined class method" do
    refute_respond_to MyClass, :undefined_original_for_after

    assert_silent do
      MyClass.singleton_class.class_eval do
        sink_after :undefined_original_for_after do
          # empty
        end
      end
    end

    refute_respond_to MyClass, :undefined_original_for_after
  end

  test "sink around undefined class method" do
    refute_respond_to MyClass, :undefined_original_for_around

    assert_silent do
      MyClass.singleton_class.class_eval do
        sink_around :undefined_original_for_around do
          # empty
        end
      end
    end

    refute_respond_to MyClass, :undefined_original_for_around
  end

  test "sink before undefined instance method" do
    instance = MyClass.new

    refute_respond_to instance, :undefined_original_for_before

    assert_silent do
      MyClass.class_eval do
        sink_before :undefined_original_for_before do
          # empty
        end
      end
    end

    refute_respond_to instance, :undefined_original_for_before
  end

  test "sink after undefined instance method" do
    instance = MyClass.new

    refute_respond_to instance, :undefined_original_for_after

    assert_silent do
      MyClass.class_eval do
        sink_after :undefined_original_for_after do
          # empty
        end
      end
    end

    refute_respond_to instance, :undefined_original_for_after
  end

  test "sink around undefined instance method" do
    instance = MyClass.new

    refute_respond_to instance, :undefined_original_for_around

    assert_silent do
      MyClass.class_eval do
        sink_around :undefined_original_for_around do
          # empty
        end
      end
    end

    refute_respond_to instance, :undefined_original_for_around
  end

  test "sink before usage" do
    assert_silent do
      MyClass.class_eval do
        sink_before :undefined_original_for_before do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_before :undefined_original_for_before
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_before do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_before
      end
    end
  end

  test "sink after usage" do
    assert_silent do
      MyClass.class_eval do
        sink_after :undefined_original_for_after do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_after :undefined_original_for_after
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_after do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_after
      end
    end
  end

  test "sink around usage" do
    assert_silent do
      MyClass.class_eval do
        sink_around :undefined_original_for_around do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_around :undefined_original_for_around
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_around do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        sink_around
      end
    end
  end

  test "presafe sink before instance method raises exceptions" do
    instance = MyClass.new
    assert_raises(StandardError) { instance.original_for_presafe_before }
  end

  test "presafe sink after instance method raises exceptions" do
    instance = MyClass.new
    assert_raises(StandardError) { instance.original_for_presafe_after }
  end

  test "presafe sink around instance method raises exceptions" do
    instance = MyClass.new
    assert_raises(StandardError) { instance.original_for_presafe_around }
  end

  test "presafe sink before usage" do
    assert_silent do
      MyClass.class_eval do
        presafe_sink_before :undefined_original_for_before do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_before :undefined_original_for_before
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_before do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_before
      end
    end
  end

  test "presafe sink after usage" do
    assert_silent do
      MyClass.class_eval do
        presafe_sink_after :undefined_original_for_after do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_after :undefined_original_for_after
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_after do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_after
      end
    end
  end

  test "presafe sink around usage" do
    assert_silent do
      MyClass.class_eval do
        presafe_sink_around :undefined_original_for_around do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_around :undefined_original_for_around
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_around do
          # empty
        end
      end
    end

    assert_raises(ArgumentError) do
      MyClass.class_eval do
        presafe_sink_around
      end
    end
  end

  module GreeterHelpers
    def build_greeter
      Class.new do
        extend Aikido::Zen::Sinks::DSL

        def greet(name)
          "hello #{name}"
        end
      end
    end

    def prepend_wrapper(klass, label)
      klass.prepend(Module.new do
        define_method(:greet) { |name| "#{label}(#{super(name)})" }
      end)
    end

    def alias_wrapper(klass, label)
      original = :"#{label}_original_greet"

      klass.class_eval do
        alias_method original, :greet

        define_method(:greet) { |name| "#{label}(#{send(original, name)})" }
      end
    end
  end

  class OriginalInstanceMethodTest < ActiveSupport::TestCase
    include GreeterHelpers

    test "patches a method when a module is prepended" do
      klass = build_greeter
      prepend_wrapper(klass, "prepended")

      original = klass.original_instance_method(:greet)
      klass.class_eval do
        define_method(:greet) { |name| "patched(#{original.bind_call(self, name)})" }
      end

      assert_equal "prepended(patched(hello Zen))", klass.new.greet("Zen")
    end

    test "aliases the original method when a module is prepended" do
      klass = build_greeter
      prepend_wrapper(klass, "prepended")

      klass.alias_original_method(:original_greet, :greet)
      klass.class_eval do
        define_method(:greet) { |name| "patched(#{original_greet(name)})" }
      end

      assert_equal "prepended(patched(hello Zen))", klass.new.greet("Zen")
    end

    test "patches an inherited method when a module is prepended" do
      klass = Class.new(build_greeter)
      prepend_wrapper(klass, "prepended")

      original = klass.original_instance_method(:greet)
      klass.class_eval do
        define_method(:greet) { |name| "patched(#{original.bind_call(self, name)})" }
      end

      assert_equal "prepended(patched(hello Zen))", klass.new.greet("Zen")
    end

    test "aliases an inherited method when a module is prepended" do
      klass = Class.new(build_greeter)
      prepend_wrapper(klass, "prepended")

      klass.alias_original_method(:original_greet, :greet)
      klass.class_eval do
        define_method(:greet) { |name| "patched(#{original_greet(name)})" }
      end

      assert_equal "prepended(patched(hello Zen))", klass.new.greet("Zen")
    end
  end

  class PrependedModuleTest < ActiveSupport::TestCase
    include GreeterHelpers

    test "presafe sink before runs once when a module is prepended before the sink method is defined" do
      klass = build_greeter
      prepend_wrapper(klass, "prepended")
      calls = []
      klass.presafe_sink_before(:greet) { |name| calls << name }

      assert_equal "prepended(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink after runs once when a module is prepended before the sink method is defined" do
      klass = build_greeter
      prepend_wrapper(klass, "prepended")
      calls = []
      klass.presafe_sink_after(:greet) { |_result, name| calls << name }

      assert_equal "prepended(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink around runs once when a module is prepended before the sink method is defined" do
      klass = build_greeter
      prepend_wrapper(klass, "prepended")
      calls = []
      klass.presafe_sink_around(:greet) do |original_call, name|
        calls << name
        original_call.call
      end

      assert_equal "prepended(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink before runs once when a module is prepended after the sink method is defined" do
      klass = build_greeter
      calls = []
      klass.presafe_sink_before(:greet) { |name| calls << name }
      prepend_wrapper(klass, "prepended")

      assert_equal "prepended(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink after runs once when a module is prepended after the sink method is defined" do
      klass = build_greeter
      calls = []
      klass.presafe_sink_after(:greet) { |_result, name| calls << name }
      prepend_wrapper(klass, "prepended")

      assert_equal "prepended(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink around runs once when a module is prepended after the sink method is defined" do
      klass = build_greeter
      calls = []
      klass.presafe_sink_around(:greet) do |original_call, name|
        calls << name
        original_call.call
      end
      prepend_wrapper(klass, "prepended")

      assert_equal "prepended(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink before runs once when several modules are prepended" do
      klass = build_greeter
      prepend_wrapper(klass, "inner")
      prepend_wrapper(klass, "outer")
      calls = []
      klass.presafe_sink_before(:greet) { |name| calls << name }

      assert_equal "outer(inner(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink after runs once when several modules are prepended" do
      klass = build_greeter
      prepend_wrapper(klass, "inner")
      prepend_wrapper(klass, "outer")
      calls = []
      klass.presafe_sink_after(:greet) { |_result, name| calls << name }

      assert_equal "outer(inner(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink around runs once when several modules are prepended" do
      klass = build_greeter
      prepend_wrapper(klass, "inner")
      prepend_wrapper(klass, "outer")
      calls = []
      klass.presafe_sink_around(:greet) do |original_call, name|
        calls << name
        original_call.call
      end

      assert_equal "outer(inner(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end
  end

  class AliasedMethodTest < ActiveSupport::TestCase
    include GreeterHelpers

    test "presafe sink before runs once when the method was aliased before the sink method is defined" do
      klass = build_greeter
      alias_wrapper(klass, "aliased")
      calls = []
      klass.presafe_sink_before(:greet) { |name| calls << name }

      assert_equal "aliased(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink after runs once when the method was aliased before the sink method is defined" do
      klass = build_greeter
      alias_wrapper(klass, "aliased")
      calls = []
      klass.presafe_sink_after(:greet) { |_result, name| calls << name }

      assert_equal "aliased(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink around runs once when the method was aliased before the sink method is defined" do
      klass = build_greeter
      alias_wrapper(klass, "aliased")
      calls = []
      klass.presafe_sink_around(:greet) do |original_call, name|
        calls << name
        original_call.call
      end

      assert_equal "aliased(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink before runs once when the method is aliased after the sink method is defined" do
      klass = build_greeter
      calls = []
      klass.presafe_sink_before(:greet) { |name| calls << name }
      alias_wrapper(klass, "aliased")

      assert_equal "aliased(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink after runs once when the method is aliased after the sink method is defined" do
      klass = build_greeter
      calls = []
      klass.presafe_sink_after(:greet) { |_result, name| calls << name }
      alias_wrapper(klass, "aliased")

      assert_equal "aliased(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink around runs once when the method is aliased after the sink method is defined" do
      klass = build_greeter
      calls = []
      klass.presafe_sink_around(:greet) do |original_call, name|
        calls << name
        original_call.call
      end
      alias_wrapper(klass, "aliased")

      assert_equal "aliased(hello Zen)", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink before runs once when the method is aliased several times" do
      klass = build_greeter
      alias_wrapper(klass, "inner")
      alias_wrapper(klass, "outer")
      calls = []
      klass.presafe_sink_before(:greet) { |name| calls << name }

      assert_equal "outer(inner(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink after runs once when the method is aliased several times" do
      klass = build_greeter
      alias_wrapper(klass, "inner")
      alias_wrapper(klass, "outer")
      calls = []
      klass.presafe_sink_after(:greet) { |_result, name| calls << name }

      assert_equal "outer(inner(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink around runs once when the method is aliased several times" do
      klass = build_greeter
      alias_wrapper(klass, "inner")
      alias_wrapper(klass, "outer")
      calls = []
      klass.presafe_sink_around(:greet) do |original_call, name|
        calls << name
        original_call.call
      end

      assert_equal "outer(inner(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end
  end

  class AliasedAndPrependedMethodTest < ActiveSupport::TestCase
    include GreeterHelpers

    test "presafe sink before runs once when the method was aliased and a module prepended before the sink method is defined" do
      klass = build_greeter
      alias_wrapper(klass, "aliased")
      prepend_wrapper(klass, "prepended")
      calls = []
      klass.presafe_sink_before(:greet) { |name| calls << name }

      assert_equal "prepended(aliased(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink after runs once when the method was aliased and a module prepended before the sink method is defined" do
      klass = build_greeter
      alias_wrapper(klass, "aliased")
      prepend_wrapper(klass, "prepended")
      calls = []
      klass.presafe_sink_after(:greet) { |_result, name| calls << name }

      assert_equal "prepended(aliased(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end

    test "presafe sink around runs once when the method was aliased and a module prepended before the sink method is defined" do
      klass = build_greeter
      alias_wrapper(klass, "aliased")
      prepend_wrapper(klass, "prepended")
      calls = []
      klass.presafe_sink_around(:greet) do |original_call, name|
        calls << name
        original_call.call
      end

      assert_equal "prepended(aliased(hello Zen))", klass.new.greet("Zen")
      assert_equal ["Zen"], calls
    end
  end
end
