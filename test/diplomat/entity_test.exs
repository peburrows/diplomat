defmodule Diplomat.EntityTest do
  use ExUnit.Case
  alias Diplomat.{Entity, Value, Key}
  alias Diplomat.Proto.Value, as: PbValue
  alias Diplomat.Proto.Entity, as: PbEntity

  describe "Entity.new/1" do
    test "given a props struct" do
      props = %TestStruct{foo: "bar"}
      assert Entity.new(props) ==
        %Entity{properties: %{
          "foo" => %Value{value: "bar", exclude_from_indexes: false}}}
    end

    test "given a props map" do
      props = %{"foo" => "bar"}
      assert Entity.new(props) ==
        %Entity{properties: %{
          "foo" => %Value{value: "bar", exclude_from_indexes: false}}}
    end
  end

  describe "Entity.new/2" do
    test "given a props and opts" do
      props = %{"foo" => "bar"}
      opts = [exclude_from_indexes: :foo]
      assert Entity.new(props, opts) ==
        %Entity{properties: %{
          "foo" => %Value{value: "bar", exclude_from_indexes: true}}}
    end

    test "given props and a kind" do
      props = %{"foo" => "bar"}
      kind = "TestKind"
      assert Entity.new(props, kind) ==
        %Entity{
          kind: kind,
          key: %Key{kind: kind, id: nil},
          properties: %{
            "foo" => %Value{value: "bar", exclude_from_indexes: false}}}
    end

    test "given props and a key" do
      props = %{"foo" => "bar"}
      key = Key.new(kind: "TestKind", id: "1")
      assert Entity.new(props, key) ==
        %Entity{
          kind: key.kind,
          key: key,
          properties: %{
            "foo" => %Value{value: "bar", exclude_from_indexes: false}}}
    end

    test "given props and opts with a nested entity" do
      props = %{"foo" => %{"bar" => "baz"}}
      opts = [exclude_from_indexes: [foo: :bar]]
      nested_entity = %Entity{
        properties: %{
          "bar" => %Value{value: "baz", exclude_from_indexes: true}}}
      assert Entity.new(props, opts) ==
        %Entity{
          properties: %{
            "foo" => %Value{value: nested_entity, exclude_from_indexes: false}}}
    end
  end

  describe "Entity.new/3" do
    test "given props, a kind, and opts" do
      props = %{"foo" => "bar"}
      kind = "TestKind"
      opts = [exclude_from_indexes: :foo]
      assert Entity.new(props, kind, opts) ==
        %Entity{
          kind: kind,
          key: %Key{kind: kind, id: nil},
          properties: %{
            "foo" => %Value{value: "bar", exclude_from_indexes: true}}}
    end

    test "given props, a key, and opts" do
      props = %{"foo" => "bar"}
      key = Key.new(kind: "TestKind", id: "1")
      opts = [exclude_from_indexes: :foo]
      assert Entity.new(props, key, opts) ==
        %Entity{
          kind: key.kind,
          key: key,
          properties: %{
            "foo" => %Value{value: "bar", exclude_from_indexes: true}}}
    end

    test "given props, a kind, and a string id" do
      props = %{"foo" => "bar"}
      kind = "TestKind"
      id = "1"
      key = %Key{kind: kind, name: id}
      assert Entity.new(props, kind, id) ==
        %Entity{
          kind: key.kind,
          key: key,
          properties: %{
            "foo" => %Value{value: "bar", exclude_from_indexes: false}}}
    end
  end

  describe "Entity.new/4" do
    test "given props, a kind, a string id, and opts" do
      props = %{"foo" => "bar"}
      kind = "TestKind"
      id = "1"
      opts = [exclude_from_indexes: :foo]
      key = %Key{kind: kind, name: id}
      assert Entity.new(props, kind, id, opts) ==
        %Entity{
          kind: key.kind,
          key: key,
          properties: %{
            "foo" => %Value{value: "bar", exclude_from_indexes: true}}}
    end
  end

  test "some JSON w/o null values" do
    ent = ~s<{"id":1089,"log_type":"view","access_token":"778efaf8333b2ac840f097448154bb6b","ip_address":"127.0.0.1","created_at":"2016-01-28T23:03:27.000Z","updated_at":"2016-01-28T23:03:27.000Z","log_guid":"2016-1-0b68c093a68b4bb5b16b","user_guid":"58GQA26TZ567K3C65VVN","vbid":"12345","brand":"vst","user_agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.111 Safari/537.36"}>
            |> Poison.decode!
            |> Diplomat.Entity.proto
    assert <<_::binary>> = Diplomat.Proto.Entity.encode(ent)
  end

  test "decode proto" do
    ent = %PbEntity{
      key: Key.new("User", 1) |> Key.proto,
      properties: [
        {"name", %PbValue{value_type: {:string_value, "elixir"}}}
      ]
    }
    ent |> PbEntity.encode |> PbEntity.decode
  end

  test "some JSON with null values" do
    ent = ~s<{"geo_lat":null,"geo_long":null,"id":1089,"log_type":"view","access_token":"778efaf8333b2ac840f097448154bb6b","ip_address":"127.0.0.1","created_at":"2016-01-28T23:03:27.000Z","updated_at":"2016-01-28T23:03:27.000Z","log_guid":"2016-1-0b68c093a68b4bb5b16b","user_guid":"58GQA26TZ567K3C65VVN","vbid":"12345","brand":"vst","user_agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.111 Safari/537.36"}>
            |> Poison.decode!
            |> Diplomat.Entity.proto

    # ensure we can encode this crazy thing
    assert <<_::binary>> = Diplomat.Proto.Entity.encode(ent)
  end

  test "converting to proto from Entity" do
    proto = %Entity{properties: %{"hello" => "world"}} |> Entity.proto

    assert %Diplomat.Proto.Entity{
      properties: [
        {"hello", %Diplomat.Proto.Value{value_type: {:string_value, "world"}}}
      ]
    } = proto
  end

  @entity %Diplomat.Proto.Entity{
    key: %Diplomat.Proto.Key{
      path: [%Diplomat.Proto.Key.PathElement{kind: "Random", id_type: {:id, 1234567890}}]
    },
    properties: %{
      "hello" => %Diplomat.Proto.Value{value_type: {:string_value, "world"}},
      "math" => %Diplomat.Proto.Value{value_type: {:entity_value, %Diplomat.Proto.Entity{}}}
    }
  }

  test "converting from a protobuf struct" do
    assert %Entity{
      key: %Key{kind: "Random", id: 1234567890},
      properties: %{
        "math" => %Value{value: %Entity{}},
        "hello" => %Value{value: "world"}
      }
    } = Entity.from_proto(@entity)
  end

  test "generating an Entity from a flat map" do
    map = %{"access_token" => "778efaf8333b2ac840f097448154bb6b", "brand" => "vst",
            "geo_lat" => nil, "geo_long" => nil, "id" => 1089, "ip_address" => "127.0.0.1",
            "log_guid" => "2016-1-0b68c093a68b4bb5b16b", "log_type" => "view",
            "updated_at" => "2016-01-28T23:03:27.000Z",
            "user_agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.111 Safari/537.36",
            "user_guid" => "58GQA26TZ567K3C65VVN", "vbid" => "12345"}
    ent = Entity.new(map, "Log")
    assert map |> Map.keys |> length == ent.properties |> Map.keys |> length
    assert ent.kind == "Log"
  end

  test "generating an Entity from a nested map" do
    ent = %{"person" => %{"firstName" => "Phil", "lastName" => "Burrows"}} |> Entity.new("Person")

    assert ent.kind == "Person"
    assert ent.properties |> Map.to_list |> length == 1

    first_property = ent.properties |> Map.to_list |> List.first
    {"person", person_val} = first_property

    assert %Diplomat.Value{
      value: %Diplomat.Entity{
        properties: %{
          "firstName" => %Value{value: "Phil"},
          "lastName" => %Value{value: "Burrows"}
        }
      }
    } = person_val
  end

  defmodule Person do
    defstruct [:firstName, :lastName, :address, :dogs]
  end

  defmodule Dog do
    defstruct [:name]
  end

  defmodule Address do
    defstruct [:city, :state]
  end

  test "generating an Entity from a nested struct" do
    person = %Person{
      firstName: "Phil",
      lastName: "Burrows",
      address: %Address{city: "Seattle", state: "WA"},
      dogs: [%Dog{name: "fido"}]}
    ent = %{"person" => person} |> Entity.new("Person")

    assert ent.kind == "Person"
    assert ent.properties |> Map.to_list |> length == 1

    first_property = ent.properties |> Map.to_list |> List.first
    {"person", _person_val} = first_property

    expected_properties = %{
      "person" => %{
        "firstName" => "Phil",
        "lastName" => "Burrows",
        "address" => %{"city" => "Seattle", "state" => "WA"},
        "dogs" => [%{"name" => "fido"}]}}
    assert expected_properties == Entity.properties(ent)
    assert %Diplomat.Entity{key: %Diplomat.Key{id: nil, kind: "Person", name: nil,
        namespace: nil, parent: nil, project_id: nil}, kind: "Person",
      properties: %{"person" => %Diplomat.Value{value: %Diplomat.Entity{key: nil,
            kind: nil,
            properties: %{"address" => %Diplomat.Value{value: %Diplomat.Entity{key: nil,
                  kind: nil,
                  properties: %{"city" => %Diplomat.Value{value: "Seattle"},
                    "state" => %Diplomat.Value{value: "WA"}}}},
              "dogs" => %Diplomat.Value{value: [%Diplomat.Value{value: %Diplomat.Entity{key: nil,
                      kind: nil,
                      properties: %{"name" => %Diplomat.Value{value: "fido"}}}}]},
              "firstName" => %Diplomat.Value{value: "Phil"},
              "lastName" => %Diplomat.Value{value: "Burrows"}}}}}} = ent
  end


  test "encoding an entity that has a nested entity" do
    ent = %{"person" => %{"firstName" => "Phil"}} |> Entity.new("Person")
    assert <<_ :: binary>> = ent |> Entity.proto |> Diplomat.Proto.Entity.encode
  end

  test "pulling properties properties" do
    ent = %{"person" => %{"firstName" => "Phil"}} |> Entity.new("Person")
    assert %{"person" => %{"firstName" => "Phil"}} == ent |> Entity.properties
  end

  test "pulling properties of arrays of properties" do
    properties = %{"person" => %{"firstName" => "Phil", "dogs" => [%{"name" => "Fido"}, %{"name" => "Woofer"}]}}
    # cast to proto
    ent = properties |> Entity.new("Person") |> Entity.proto |> Entity.from_proto
    assert  properties == ent |> Entity.properties
  end


  test "property names are converted to strings" do
    entity = Entity.new(%{:hello => "world"}, "CodeSnippet")
    assert %{"hello" => "world"} == Entity.properties(entity)
  end

  test "building an entity with a custom key" do
    entity = Entity.new(%{"hi" => "there"}, %Key{kind: "Message", namespace: "custom"})
    assert %Entity{
      properties: %{},
      key: %Key{
        kind: "Message",
        namespace: "custom"
      }
    } = entity
  end

  # test "encoding an entity with a namespace as a protobuf" do
  #   entity = Entity.new(%{"hello" => "world"}, %Key{kind: "Message", namespace: "whatever"})
  #   assert <<>> = entity |> Entity.proto |> Diplomat.Proto.Entity.encode
  # end
end
