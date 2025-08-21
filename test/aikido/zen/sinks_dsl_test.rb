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
end
