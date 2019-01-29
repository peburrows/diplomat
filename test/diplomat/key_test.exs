defmodule Diplomat.KeyTest do
  use ExUnit.Case
  alias Diplomat.{Key}
  alias Diplomat.Proto.Key, as: PbKey

  test "creating a new key with a name" do
    assert %Key{
             kind: "Log",
             name: "testing",
             id: nil
           } = Key.new("Log", "testing")
  end

  test "creating a new key with an id" do
    assert %Key{
             kind: "Log",
             name: nil,
             id: 123
           } = Key.new("Log", 123)
  end

  test "creating a key with an id and parent" do
    parent = Key.new("Asset")

    assert %Key{
             parent: ^parent,
             kind: "Author",
             id: 123,
             name: nil
           } = Key.new("Author", 123, parent)
  end

  test "creating a key with a name and parent" do
    parent = Key.new("Asset")

    assert %Key{
             parent: ^parent,
             kind: "Author",
             id: nil,
             name: "20k-author"
           } = Key.new("Author", "20k-author", parent)
  end

  test "creating a kew via an array" do
    assert %Key{
             kind: "Book",
             id: 1
           } = ["Book", 1] |> Key.from_path()
  end

  test "creating a key with a parent via an array" do
    assert %Key{
             kind: "Author",
             id: 2,
             parent: %Key{
               kind: "Book",
               id: 1
             }
           } = [["Book", 1], ["Author", 2]] |> Key.from_path()
  end

  test "creating a key with multiple ancestors via an array" do
    assert %Key{
             kind: "Name",
             id: 3,
             parent: %Key{
               kind: "Author",
               id: 2,
               parent: %Key{
                 kind: "Book",
                 id: 1
               }
             }
           } = [["Book", 1], ["Author", 2], ["Name", 3]] |> Key.from_path()
  end

  test "generating the path without ancestors" do
    assert [["Author", 123]] == Key.new("Author", 123) |> Key.path()
    assert [["Author", "hello"]] == Key.new("Author", "hello") |> Key.path()
  end

  test "generating a path with a single parent" do
    parent = Key.new("Asset", 123)
    assert [["Asset", 123], ["Author", 123]] == Key.new("Author", 123, parent) |> Key.path()
  end

  test "generating a path with muliple ancestors" do
    grandparent = Key.new("Collection", "Shakespeare")
    parent = Key.new("Play", "Romeo+Juliet", grandparent)
    child = Key.new("Act", "ActIII", parent)

    assert [
             ["Collection", "Shakespeare"],
             ["Play", "Romeo+Juliet"],
             ["Act", "ActIII"]
           ] == Key.path(child)
  end

  test "converting a single key to a protobuf" do
    pb = Key.new("Book", "Romeo+Juliet") |> Key.proto()

    assert %PbKey{
             path: [
               %PbKey.PathElement{kind: "Book", id_type: {:name, "Romeo+Juliet"}}
             ]
           } = pb

    assert <<_::binary>> = pb |> PbKey.encode()
  end

  test "converting a key with ancestors to a protobuf" do
    pb = Key.new("Book", "Romeo+Juliet", Key.new("Collection", "Shakespeare")) |> Key.proto()

    assert %PbKey{
             path: [
               %PbKey.PathElement{kind: "Collection", id_type: {:name, "Shakespeare"}},
               %PbKey.PathElement{kind: "Book", id_type: {:name, "Romeo+Juliet"}}
             ]
           } = pb

    assert <<_::binary>> = pb |> PbKey.encode()
  end

  test "converting an incomplete key to a protobuf" do
    pb = Key.new("Book") |> Key.proto()

    assert %PbKey{
             path: [
               %PbKey.PathElement{kind: "Book", id_type: nil}
             ]
           } = pb

    assert <<_::binary>> = pb |> PbKey.encode()
  end

  test "creating a key from a protobuf struct" do
    key = %Key{
      kind: "User",
      name: "dev@philburrows.com",
      project_id: "diplo",
      namespace: "test"
    }

    pb_key = %PbKey{
      partition_id: Diplomat.Proto.PartitionId.new(project_id: "diplo", namespace_id: "test"),
      path: [
        PbKey.PathElement.new(kind: "User", id_type: {:name, "dev@philburrows.com"})
      ]
    }

    assert ^key = pb_key |> Key.from_proto()
  end

  test "creating a key from a nested key protobuf struct" do
    assert %Key{
             project_id: "diplo",
             namespace: "test",
             kind: "Name",
             parent: %Key{
               kind: "UserDetails",
               id: 1,
               parent: %Key{
                 kind: "User",
                 name: "dev@philburrows.com"
               }
             }
           } =
             %PbKey{
               partition_id:
                 Diplomat.Proto.PartitionId.new(project_id: "diplo", namespace_id: "test"),
               path: [
                 PbKey.PathElement.new(kind: "User", id_type: {:name, "dev@philburrows.com"}),
                 PbKey.PathElement.new(kind: "UserDetails", id_type: {:id, 1}),
                 PbKey.PathElement.new(kind: "Name", id_type: {:name, "phil-name"})
               ]
             }
             |> Key.from_proto()
  end

  test "converting a key to a proto struct includes the namespace if defined" do
    assert %PbKey{
             partition_id: %Diplomat.Proto.PartitionId{
               namespace_id: "custom",
               project_id: "random"
             }
           } = %Key{namespace: "custom", project_id: "random"} |> Key.proto()
  end

  test "reads proto with an incomplete key" do
    key = %Key{kind: "Test"}
    assert key == key |> Key.proto() |> Key.from_proto()
  end

  test "Key.incomplete?" do
    assert %Key{kind: "Asset"} |> Key.incomplete?()
    refute %Key{id: 1} |> Key.incomplete?()
    refute %Key{name: "test"} |> Key.incomplete?()
    refute [["Book", 1], ["Author", 2]] |> Key.from_path() |> Key.incomplete?()
  end

  test "Key.complete?" do
    refute %Key{kind: "Asset"} |> Key.complete?()
    assert %Key{id: 1} |> Key.complete?()
    assert %Key{name: "test"} |> Key.complete?()
    assert [["Asset", 1], ["Random", 2]] |> Key.from_path() |> Key.complete?()
  end
end
