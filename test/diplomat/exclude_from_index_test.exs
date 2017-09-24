defmodule Diplomat.ExcludeFromIndexTest do
    use ExUnit.Case
    alias Diplomat.Proto.CommitResponse
    alias Diplomat.Proto.CommitRequest
    alias Diplomat.Proto.MutationResult
    alias Diplomat.Proto.Mutation

    alias Diplomat.{Key, Entity}

    test "inserting an entity with exclude_from_indexes field" do
        {:ok, project} = Goth.Config.get(:project_id)
        {kind, name}   = {"TestBook", "my-book-unique-id"}
        
        entity = Entity.new(
          %{
            "name" => "My awesome book", 
            "author" => "Phil Burrows",
            "long_field" => String.duplicate("A very long field!", 1500)},
          kind, 
          name,
          ["long_field"]
        ) |> Entity.insert
        
        
        
    end
end