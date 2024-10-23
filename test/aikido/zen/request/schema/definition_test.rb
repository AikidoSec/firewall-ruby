# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Request::Schema::DefinitionTest < ActiveSupport::TestCase
  def build_schema(data)
    Aikido::Zen::Request::Schema::Definition.new(data)
  end

  test "#merge with same object duplicates" do
    schema = build_schema(type: "string")

    assert_equal schema, schema.merge(schema)
    refute_same schema, schema.merge(schema) # new instance
  end

  test "#merge with nil duplicates" do
    schema = build_schema(type: "string")

    assert_equal schema, schema | nil
    refute_same schema, schema | nil
  end

  test "#merge with the empty schema duplicates" do
    schema = build_schema(type: "string")
    empty = Aikido::Zen::Request::Schema::EMPTY_SCHEMA

    assert_equal schema, schema | empty
    refute_same schema, schema | empty
  end

  test "#merge primitive with itself results in the same type" do
    ["null", "string", "number", "integer", "boolean"].each do |type|
      schema_1 = build_schema(type: type)
      schema_2 = build_schema(type: type)

      assert_equal build_schema(type: type), schema_1 | schema_2
      assert_equal build_schema(type: type), schema_2 | schema_1
    end
  end

  test "#merge null with a primitive type results in optional type" do
    null = build_schema(type: "null")
    bool = build_schema(type: "boolean")

    assert_equal build_schema(type: "boolean", optional: true), null | bool
    assert_equal build_schema(type: "boolean", optional: true), bool | null
  end

  test "#merge null with string results in optional string" do
    null = build_schema(type: "null")
    string = build_schema(type: "string")

    assert_equal build_schema(type: "string", optional: true), null | string
    assert_equal build_schema(type: "string", optional: true), string | null
  end

  test "#merge number with null results in optional number" do
    null = build_schema(type: "null")
    number = build_schema(type: "number")

    assert_equal build_schema(type: "number", optional: true), number | null
    assert_equal build_schema(type: "number", optional: true), null | number
  end

  test "#merge array with null results in optional array" do
    null = build_schema(type: "null")
    array = build_schema(type: "array", items: {type: "string"})

    assert_equal build_schema(type: "array", items: {type: "string"}, optional: true),
      array | null
    assert_equal build_schema(type: "array", items: {type: "string"}, optional: true),
      null | array
  end

  test "#merge object with null results in optional object" do
    null = build_schema(type: "null")
    obj = build_schema(type: "object", properties: {"foo" => {type: "string"}})

    assert_equal build_schema(
      type: "object", properties: {"foo" => {type: "string"}}, optional: true
    ), obj | null
    assert_equal build_schema(
      type: "object", properties: {"foo" => {type: "string"}}, optional: true
    ), null | obj
  end

  test "#merge integer with number results in number" do
    integer = build_schema(type: "integer")
    number = build_schema(type: "number")

    assert_equal build_schema(type: "number"), integer | number
    assert_equal build_schema(type: "number"), number | integer
  end

  test "#merge primitive types results in a combined type" do
    ["string", "number", "integer", "boolean"].combination(2) do |(left, right)|
      next if [left, right].sort == ["integer", "number"] # covered by other test

      left_type = build_schema(type: left)
      right_type = build_schema(type: right)

      assert_equal build_schema(type: [left, right].sort), left_type | right_type
      assert_equal build_schema(type: [right, left].sort), right_type | left_type
    end
  end

  test "#merge primitive with combined type results in adding to combined" do
    combined = build_schema(type: ["number", "boolean"])
    string = build_schema(type: "string")

    assert_equal build_schema(type: ["boolean", "number", "string"]), combined | string
    assert_equal build_schema(type: ["boolean", "number", "string"]), string | combined
  end

  test "#merge primitive with combined type does not repeat types" do
    combined = build_schema(type: ["number", "string"])
    string = build_schema(type: "string")

    assert_equal build_schema(type: ["number", "string"]), combined | string
    assert_equal build_schema(type: ["number", "string"]), string | combined
  end

  test "#merge primitive with object results in combined type" do
    object = build_schema(
      type: "object",
      properties: {"prop" => build_schema(type: "string")}
    )

    ["string", "number", "integer", "boolean"].each do |type|
      primitive = build_schema(type: type)
      expected = build_schema(
        type: ["object", type].sort,
        properties: {"prop" => build_schema(type: "string")}
      )

      assert_equal expected, primitive | object
      assert_equal expected, object | primitive
    end
  end

  test "#merge arrays without items sub-schema" do
    ary_1 = build_schema(type: "array")
    ary_2 = build_schema(type: "array")

    assert_equal build_schema(type: "array"), ary_1 | ary_2
    assert_equal build_schema(type: "array"), ary_2 | ary_1
  end

  test "#merge arrays of the same sub-type results in a copy of the schema" do
    ary_1 = build_schema(type: "array", items: build_schema(type: "string"))
    ary_2 = build_schema(type: "array", items: build_schema(type: "string"))

    assert_equal ary_1, ary_1 | ary_2
    assert_equal ary_1, ary_2 | ary_1
  end

  test "#merge arrays results in an array with a combined item sub-schema" do
    string_ary = build_schema(type: "array", items: build_schema(type: "string"))
    number_ary = build_schema(type: "array", items: build_schema(type: "number"))

    expected = build_schema(
      type: "array",
      items: build_schema(type: ["number", "string"])
    )

    assert_equal expected, string_ary | number_ary
    assert_equal expected, number_ary | string_ary
  end

  test "#merge arrays where one doesn't have items sub-schema" do
    plain_ary = build_schema(type: "array")
    string_ary = build_schema(type: "array", items: build_schema(type: "string"))

    expected = build_schema(
      type: "array",
      items: build_schema(type: "string")
    )

    assert_equal expected, string_ary | plain_ary
    assert_equal expected, plain_ary | string_ary
  end

  test "#merge objects without properties" do
    obj_1 = build_schema(type: "object")
    obj_2 = build_schema(type: "object")

    assert_equal build_schema(type: "object"), obj_1 | obj_2
    assert_equal build_schema(type: "object"), obj_2 | obj_1
  end

  test "#merge objects with the same properties' sub-schema results in a copy" do
    object_1 = build_schema(
      type: "object",
      properties: {
        foo: build_schema(type: "string"),
        bar: build_schema(type: "number")
      }
    )
    object_2 = build_schema(
      type: "object",
      properties: {
        foo: build_schema(type: "string"),
        bar: build_schema(type: "number")
      }
    )

    assert_equal object_1, object_1 | object_2
    assert_equal object_1, object_2 | object_1
  end

  test "#merge objects results in an object with the combined properties" do
    object_1 = build_schema(
      type: "object",
      properties: {
        foo: build_schema(type: "string"),
        bar: build_schema(type: "number")
      }
    )
    object_2 = build_schema(
      type: "object",
      properties: {
        foo: build_schema(type: "number"),
        bar: build_schema(type: "string")
      }
    )

    expected = build_schema(
      type: "object",
      properties: {
        foo: build_schema(type: ["number", "string"]),
        bar: build_schema(type: ["number", "string"])
      }
    )

    assert_equal expected, object_1 | object_2
    assert_equal expected, object_2 | object_1
  end

  test "#merge objects treats keys missing on either object as optional" do
    object_1 = build_schema(
      type: "object",
      properties: {
        foo: build_schema(type: "string"),
        bar: build_schema(type: "number")
      }
    )
    object_2 = build_schema(
      type: "object",
      properties: {
        foo: build_schema(type: "string"),
        baz: build_schema(type: "number")
      }
    )

    expected = build_schema(
      type: "object",
      properties: {
        foo: build_schema(type: "string"),
        bar: build_schema(type: "number", optional: true),
        baz: build_schema(type: "number", optional: true)
      }
    )

    assert_equal expected, object_1 | object_2
    assert_equal expected, object_2 | object_1
  end

  class EmptySchemaTest < ActiveSupport::TestCase
    setup { @schema = Aikido::Zen::Request::Schema::EMPTY_SCHEMA }

    test "serializes to nothing" do
      assert_nil @schema.as_json
    end

    test "merging an empty schema with nil returns the empty_schema" do
      assert_same @schema, @schema | nil
    end

    test "merging an empty schema with anything else returns the argument" do
      schema = Aikido::Zen::Request::Schema::Definition.new(type: "object")

      assert_same schema, @schema | schema
    end
  end
end
