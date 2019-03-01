defmodule Diplomat.TransactionTest do
  use ExUnit.Case

  alias Diplomat.{Transaction, Entity, Key}
  alias Diplomat.Proto.BeginTransactionResponse, as: TransResponse
  alias Diplomat.Proto.BeginTransactionRequest, as: TransRequest
  alias Diplomat.Proto.{CommitRequest, CommitResponse, MutationResult, Mutation, RollbackResponse}

  setup do
    bypass = Bypass.open()
    Application.put_env(:diplomat, :endpoint, "http://localhost:#{bypass.port}")
    {:ok, project} = Goth.Config.get(:project_id)
    {:ok, bypass: bypass, project: project}
  end

  test "creating a transaction from a transaction response returns a transaction" do
    assert %Transaction{id: <<1, 2, 4>>, state: :begun} =
             Transaction.from_begin_response(TransResponse.new(transaction: <<1, 2, 4>>))
  end

  test "beginning a transaction calls the server with a BeginTransactionRequest and returns a Transaction struct",
       %{bypass: bypass, project: project} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %TransRequest{project_id: nil} = TransRequest.decode(body)

      assert Regex.match?(~r{/v1/projects/#{project}:beginTransaction}, conn.request_path)
      resp = TransResponse.new(transaction: <<40, 30, 20>>) |> TransResponse.encode()
      Plug.Conn.resp(conn, 201, resp)
    end)

    trans = Transaction.begin()
    assert %Transaction{state: :begun, id: <<40, 30, 20>>} = trans
  end

  test "converting a transaction to a CommitRequest" do
    t = %Transaction{
      id: <<1, 2, 3>>,
      state: :begun,
      mutations: [
        {:update, Entity.new(%{phil: "burrows"}, "Person", "phil-burrows")},
        {:insert, Entity.new(%{jimmy: "allen"}, "Person", 12_234_324)},
        {:delete, Key.new("Person", "that-one-guy")}
      ]
    }

    commit =
      CommitRequest.new(
        mode: :TRANSACTIONAL,
        transaction_selector: {:transaction, <<1, 2, 3>>},
        mutations: [
          Mutation.new(
            operation:
              {:update,
               Entity.new(%{phil: "burrows"}, "Person", "phil-burrows") |> Entity.proto()}
          ),
          Mutation.new(
            operation:
              {:insert, Entity.new(%{jimmy: "allen"}, "Person", 12_234_324) |> Entity.proto()}
          ),
          Mutation.new(operation: {:delete, Key.new("Person", "that-one-guy") |> Key.proto()})
        ]
      )

    assert ^commit = Transaction.to_commit_proto(t)
  end

  test "rolling back a transaction calls the server with the RollbackRequest", %{
    bypass: bypass,
    project: project
  } do
    Bypass.expect(bypass, fn conn ->
      assert Regex.match?(~r{/v1/projects/#{project}:rollback}, conn.request_path)
      # the rsponse is empty
      Plug.Conn.resp(conn, 200, <<>>)
    end)

    {:ok, resp} = %Transaction{id: <<1>>} |> Transaction.rollback()
    assert %RollbackResponse{} = resp
  end

  test "committing a transaction calls the server with the right data and returns a successful response (whatever that is)",
       %{bypass: bypass, project: project} do
    commit =
      CommitResponse.new(
        index_updates: 0,
        mutation_results: [MutationResult.new()]
      )

    Bypass.expect(bypass, fn conn ->
      assert Regex.match?(~r{/v1/projects/#{project}:commit}, conn.request_path)
      response = commit |> CommitResponse.encode()
      Plug.Conn.resp(conn, 201, response)
    end)

    assert {:ok, ^commit} = %Transaction{id: <<1>>} |> Transaction.commit()
  end

  test "a transaction block begins and commits the transaction automatically", opts do
    assert_begin_and_commit!(opts)
    Transaction.begin(fn t -> t end)
  end

  test "we can add inserts to a transaction" do
    e = Entity.new(%{abraham: "lincoln"}, "Body", 123)
    t = %Transaction{id: 123} |> Transaction.insert(e)
    assert Enum.count(t.mutations) == 1
    assert Enum.at(t.mutations, 0) == {:insert, e}
  end

  # test "we can add insert_auto_ids to a transaction" do
  #   e = Entity.new(%{abraham: "lincoln"}, "Body")
  #   t = %Transaction{id: 123} |> Transaction.insert(e)
  #   assert Enum.count(t.insert_auto_ids) == 1
  #   assert Enum.at(t.insert_auto_ids, 0) == e
  # end

  test "find an entity within the context of a transaction", %{bypass: bypass, project: project} do
    Bypass.expect(bypass, fn conn ->
      path = "/v1/projects/#{project}"

      cond do
        Regex.match?(~r{#{path}:beginTransaction}, conn.request_path) ->
          response =
            <<10, 29, 9, 166, 1, 0, 0, 0, 0, 0, 0, 18, 18, 108, 111, 121, 97, 108, 45, 103, 108,
              97, 115, 115, 45, 49, 54, 51, 48, 48, 50>>

          Plug.Conn.resp(conn, 200, response)

        Regex.match?(~r{#{path}:lookup}, conn.request_path) ->
          response =
            <<10, 53, 10, 48, 10, 34, 10, 20, 18, 18, 108, 111, 121, 97, 108, 45, 103, 108, 97,
              115, 115, 45, 49, 54, 51, 48, 48, 50, 18, 10, 10, 5, 84, 104, 105, 110, 103, 26, 1,
              49, 26, 10, 10, 4, 116, 101, 115, 116, 18, 2, 8, 1, 32, 235, 1>>

          Plug.Conn.resp(conn, 200, response)

        true ->
          raise "Unknown request"
      end
    end)

    tx = Transaction.begin()
    result = Transaction.find(tx, %Key{id: 1})

    assert [
             %Diplomat.Entity{
               key: %Diplomat.Key{
                 id: nil,
                 kind: "Thing",
                 name: "1",
                 namespace: nil,
                 parent: nil,
                 project_id: _
               },
               kind: "Thing",
               properties: %{"test" => %Diplomat.Value{value: true}}
             }
           ] = result
  end

  test "we can add upserts to a transaction" do
    e = Entity.new(%{whatever: "yes"}, "Thing", 123)
    t = %Transaction{id: 123} |> Transaction.upsert(e)
    assert Enum.count(t.mutations) == 1
    assert Enum.at(t.mutations, 0) == {:upsert, e}
  end

  test "we can add updates to a transaction" do
    e = Entity.new(%{whatever: "yes"}, "Thing", 123)
    t = %Transaction{id: 123} |> Transaction.update(e)
    assert Enum.count(t.mutations) == 1
    assert Enum.at(t.mutations, 0) == {:update, e}
  end

  test "we can add deletes to a transaction" do
    k = Key.new("Person", 123)
    t = %Transaction{id: 123} |> Transaction.delete(k)
    assert Enum.count(t.mutations) == 1
    assert Enum.at(t.mutations, 0) == {:delete, k}
  end

  def assert_begin_and_commit!(%{bypass: bypass, project: project}) do
    Bypass.expect(bypass, fn conn ->
      if Regex.match?(~r{beginTransaction}, conn.request_path) do
        assert Regex.match?(~r{/v1/projects/#{project}:beginTransaction}, conn.request_path)
        resp = TransResponse.new(transaction: <<40, 30, 20>>) |> TransResponse.encode()
        Plug.Conn.resp(conn, 201, resp)
      else
        assert Regex.match?(~r{/v1/projects/#{project}:commit}, conn.request_path)

        resp =
          CommitResponse.new(
            mutation_result:
              MutationResult.new(
                index_updates: 0,
                insert_auto_id_key: []
              )
          )
          |> CommitResponse.encode()

        Plug.Conn.resp(conn, 201, resp)
      end
    end)
  end
end
