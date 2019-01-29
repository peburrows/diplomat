defmodule Diplomat.Entity.InsertTest do
  use ExUnit.Case
  alias Diplomat.Proto.CommitResponse
  alias Diplomat.Proto.CommitRequest
  alias Diplomat.Proto.MutationResult
  alias Diplomat.Proto.Mutation

  alias Diplomat.{Key, Entity}

  setup do
    bypass = Bypass.open()
    Application.put_env(:diplomat, :endpoint, "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass}
  end

  test "extracting keys from CommitResponse" do
    response =
      CommitResponse.new(
        mutation_results: [
          MutationResult.new(key: Key.new("Thing", 1) |> Key.proto()),
          MutationResult.new(key: Key.new("Thing", 2) |> Key.proto())
        ],
        index_updates: 2
      )

    keys = response |> Key.from_commit_proto()
    assert Enum.count(keys) == 2

    Enum.each(keys, fn k ->
      assert %Key{} = k
    end)
  end

  test "building a CommitRequest from a single Entity mutation" do
    entity = Entity.new(%{"name" => "phil"}, "Person", "phil-burrows")
    ent_proto = Entity.proto(entity)

    assert %CommitRequest{
             mutations: [
               %Mutation{operation: {:insert, ^ent_proto}}
             ],
             mode: :NON_TRANSACTIONAL
           } = Entity.commit_request([{:insert, entity}])
  end

  test "inserting a single entity", %{bypass: bypass} do
    {:ok, project} = Goth.Config.get(:project_id)
    {kind, name} = {"TestBook", "my-book-unique-id"}

    entity =
      Entity.new(
        %{"name" => "My awesome book", "author" => "Phil Burrows"},
        kind,
        name
      )

    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      # ensure we're passing in the correct data
      assert %CommitRequest{
               mutations: [
                 %Mutation{operation: {:insert, _ent}}
               ]
             } = CommitRequest.decode(body)

      assert Regex.match?(~r{/v1/projects/#{project}:commit}, conn.request_path)

      resp =
        CommitResponse.new(
          mutation_results: [
            MutationResult.new(key: Key.new(kind, name) |> Key.proto())
          ],
          index_updates: 1
        )
        |> CommitResponse.encode()

      Plug.Conn.resp(conn, 201, resp)
    end)

    keys = Entity.insert(entity)
    assert Enum.count(keys) == 1
    retkey = hd(keys)

    assert retkey.kind == kind
    assert retkey.name == name
  end

  test "a failed insert", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      resp =
        <<8, 3, 18, 22, 69, 110, 116, 105, 116, 121, 32, 105, 115, 32, 109, 105, 115, 115, 105,
          110, 103, 32, 107, 101, 121, 46>>

      Plug.Conn.resp(conn, 400, resp)
    end)

    assert {:error, status} = Entity.new(%{"a" => 1}) |> Entity.insert()

    assert %Diplomat.Proto.Status{
             code: 3,
             details: [],
             message: "Entity is missing key."
           } = status
  end
end
