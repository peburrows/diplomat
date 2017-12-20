defmodule Diplomat.ValueTest do
  use ExUnit.Case
  alias Diplomat.{Value, Entity, Key}
  alias Diplomat.Proto.Value, as: PbVal
  alias Diplomat.Proto.Key, as: PbKey
  alias Diplomat.Proto.ArrayValue, as: PbArray
  alias Diplomat.Proto.Timestamp, as: PbTimestamp
  alias Diplomat.Proto.LatLng, as: PbLatLng

  describe "Value.new/1" do
    test "given an Entity" do
      entity = Entity.new(%{"foo" => "bar"})
      assert Value.new(entity) ==
        %Value{value: entity, exclude_from_indexes: false}
    end

    test "given a Key" do
      key = Key.new("TestKind", "1")
      assert Value.new(key) ==
        %Value{value: key, exclude_from_indexes: false}
    end

    test "given a Value" do
      value = Value.new(1)
      assert Value.new(value) ==
        %Value{value: value, exclude_from_indexes: false}
    end

    test "given a struct" do
      struct = %TestStruct{foo: "bar"}
      entity = Entity.new(%{"foo" => "bar"})
      assert Value.new(struct) ==
        %Value{value: entity, exclude_from_indexes: false}
    end

    test "given a map" do
      map = %{"foo" => "bar"}
      entity = Entity.new(map)
      assert Value.new(map) ==
        %Value{value: entity, exclude_from_indexes: false}
    end

    test "given a list" do
      int = 1
      map = %{"foo" => "bar"}
      entity = Entity.new(map)
      list = [int, map]
      int_value = %Value{value: int, exclude_from_indexes: false}
      entity_value = %Value{value: entity, exclude_from_indexes: false}
      assert Value.new(list) ==
        %Value{value: [int_value, entity_value], exclude_from_indexes: false}
    end

    test "given a string" do
      string = "test"
      assert Value.new(string) ==
        %Value{value: string, exclude_from_indexes: false}
    end

    test "given an integer" do
      int = 1
      assert Value.new(int) ==
        %Value{value: int, exclude_from_indexes: false}
    end

    test "given a DateTime" do
      time = DateTime.utc_now()
      assert Value.new(time) ==
        %Value{value: time, exclude_from_indexes: false}
    end

    test "given a NaiveDateTime" do
      time = NaiveDateTime.utc_now()
      assert Value.new(time) ==
        %Value{value: time, exclude_from_indexes: false}
    end
  end

  describe "Value.new/2" do
    test "given an Entity and exclude_from_indexes is true" do
      entity = Entity.new(%{"foo" => "bar"})
      assert Value.new(entity, exclude_from_indexes: true) ==
        %Value{value: entity, exclude_from_indexes: true}
    end

    test "given a nested map and exclude_from_indexes contains an path" do
      map = %{"foo" => %{"bar" => "baz"}}
      nested_entity = %Entity{
        properties: %{
          "bar" => %Value{value: "baz", exclude_from_indexes: true}}}
      entity = %Entity{
          properties: %{
            "foo" => %Value{value: nested_entity, exclude_from_indexes: false}}}
      assert Value.new(map, exclude_from_indexes: [foo: :bar]) ==
        %Value{value: entity, exclude_from_indexes: false}
    end

    test "given a deeply nested map and exclude_from_indexes contains a path" do
      map = %{"foo" => %{"bar" => %{"baz" => "qux"}}, "foo2" => 1}
      deeply_nested_entity = %Entity{
        properties: %{
          "baz" => %Value{value: "qux", exclude_from_indexes: true}}}
      nested_entity = %Entity{
        properties: %{
          "bar" => %Value{value: deeply_nested_entity, exclude_from_indexes: false}}}
      entity = %Entity{
          properties: %{
            "foo" => %Value{value: nested_entity, exclude_from_indexes: false},
            "foo2" => %Value{value: 1, exclude_from_indexes: true}}}
      assert Value.new(map, exclude_from_indexes: [:foo2, foo: [bar: :baz]]) ==
        %Value{value: entity, exclude_from_indexes: false}
    end

    test "given a string longer than 1500 bytes and truncate is true" do
      string = 2_000 |> :crypto.strong_rand_bytes |> Base.url_encode64
      <<first :: size(1500), _ :: bitstring>> = string
      assert Value.new(string, truncate: true) ==
        %Value{value: first, exclude_from_indexes: false}
    end
  end

  describe "Value.proto/1" do
    test "given a protocol buffer value" do
      pb_val = %PbVal{}
      assert Value.proto(pb_val) == %{pb_val | exclude_from_indexes: false}
    end

    test "given a nil value" do
      assert Value.proto(nil) ==
        PbVal.new(value_type: {:null_value, :NULL_VALUE}, exclude_from_indexes: false)
    end

    test "given a Diplomat.Value struct" do
      value = Value.new(nil, exclude_from_indexes: true)
      assert Value.proto(value) ==
        PbVal.new(value_type: {:null_value, :NULL_VALUE}, exclude_from_indexes: true)
    end

    test "given a boolean value" do
      assert Value.proto(true) ==
        PbVal.new(value_type: {:boolean_value, true}, exclude_from_indexes: false)
    end

    test "given an integer value" do
      assert Value.proto(1) ==
        PbVal.new(value_type: {:integer_value, 1}, exclude_from_indexes: false)
    end

    test "given a double value" do
      assert Value.proto(1.1) ==
        PbVal.new(value_type: {:double_value, 1.1}, exclude_from_indexes: false)
    end

    test "given an atom value" do
      assert Value.proto(:foo) ==
        PbVal.new(value_type: {:string_value, "foo"}, exclude_from_indexes: false)
    end

    test "given a string value" do
      assert Value.proto("foo") ==
        PbVal.new(value_type: {:string_value, "foo"}, exclude_from_indexes: false)
    end

    test "given an invalid string value" do
      blob = <<0xFFFF :: 16>>
      assert Value.proto(blob) ==
        PbVal.new(value_type: {:blob_value, blob}, exclude_from_indexes: false)
    end

    test "given a bitstring value" do
      blob = <<1 :: size(1)>>
      assert Value.proto(blob) ==
        PbVal.new(value_type: {:blob_value, blob}, exclude_from_indexes: false)
    end

    test "given a list value" do
      map = %{"foo" => "bar"}
      array = [1, nil, map, "asdf"]
      pb_entity = map |> Entity.new() |> Entity.proto()
      pb_array = %PbArray{values: [
        %PbVal{value_type: {:integer_value, 1}, exclude_from_indexes: false},
        %PbVal{value_type: {:null_value, :NULL_VALUE}, exclude_from_indexes: false},
        %PbVal{value_type: {:entity_value, pb_entity}, exclude_from_indexes: false},
        %PbVal{value_type: {:string_value, "asdf"}, exclude_from_indexes: false}]}
      assert Value.proto(array) ==
        PbVal.new(value_type: {:array_value, pb_array}, exclude_from_indexes: false)
    end

    test "given an empty list value" do
      pb_array = %PbArray{values: []}
      assert Value.proto([]) ==
        PbVal.new(value_type: {:array_value, pb_array}, exclude_from_indexes: false)
    end

    test "given a DateTime value" do
      datetime = DateTime.utc_now()
      timestamp = DateTime.to_unix(datetime, :nanoseconds)
      pb_timestamp = %PbTimestamp{
        seconds: div(timestamp, 1_000_000_000),
        nanos: rem(timestamp, 1_000_000_000)}
      assert Value.proto(datetime) ==
        PbVal.new(value_type: {:timestamp_value, pb_timestamp}, exclude_from_indexes: false)
    end

    test "given a Diplomat.Key value" do
      key = Key.new("TestKind", "1")
      pb_key = key |> Key.proto()
      assert Value.proto(key) ==
        PbVal.new(value_type: {:key_value, pb_key}, exclude_from_indexes: false)
    end

    test "given a map value" do
      map = %{"foo" => "bar"}
      pb_entity = map |> Entity.new() |> Entity.proto()
      assert Value.proto(map) ==
        PbVal.new(value_type: {:entity_value, pb_entity}, exclude_from_indexes: false)
    end

    test "given a geo value" do
      geo = {1.0, 2.0}
      pb_latlng = %PbLatLng{latitude: 1.0, longitude: 2.0}
      assert Value.proto(geo) ==
        PbVal.new(value_type: {:geo_point_value, pb_latlng}, exclude_from_indexes: false)
    end
  end

  describe "Value.proto/2" do
    test "given a nil value and exclude_from_indexes is true" do
      assert Value.proto(nil, exclude_from_indexes: true) ==
        PbVal.new(value_type: {:null_value, :NULL_VALUE}, exclude_from_indexes: true)
    end
  end

  # ==== Value.from_proto ======
  test "creating from protobuf struct" do
    [true, 35, 3.1415, "hello", nil]
      |> Enum.each( fn(i)->
        proto = Value.proto(i)
        val   = Value.new(i)
        assert val == Value.from_proto(proto)
      end)
  end

  test "create key from protobuf key" do
    proto = %PbVal{
      value_type: {
        :key_value, %PbKey{
          path: [
            PbKey.PathElement.new(kind: "User", id_type: {:id, 1})
          ]
        }
      }
    }
    key = Value.from_proto(proto).value
    assert key.kind == "User"
    assert key.id == 1
  end

  test "creating from a protobuf struct with a list value" do
    proto = [1,2,3] |> Value.proto

    assert %Value{value: [
        %Value{value: 1}, %Value{value: 2}, %Value{value: 3}
      ]} = Value.from_proto(proto)
  end
end
