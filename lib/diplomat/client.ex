defmodule Diplomat.Client do
  alias Diplomat.{Entity, QueryResultBatch, Key}

  alias Diplomat.Proto.{
    AllocateIdsRequest,
    AllocateIdsResponse,
    CommitRequest,
    CommitResponse,
    BeginTransactionRequest,
    BeginTransactionResponse,
    RollbackRequest,
    RollbackResponse,
    RunQueryRequest,
    RunQueryResponse,
    LookupRequest,
    LookupResponse,
    Status
  }

  @moduledoc """
  Low level Google DataStore RPC client functions.
  """

  @api_version "v1"

  @type error :: {:error, Status.t()}
  @typep method :: :allocateIds | :beginTransaction | :commit | :lookup | :rollback | :runQuery

  @spec allocate_ids(AllocateIdsRequest.t()) :: list(Key.t()) | error
  @doc "Allocate ids for a list of keys with incomplete key paths"
  def allocate_ids(req) do
    req
    |> AllocateIdsRequest.encode()
    |> call(:allocateIds)
    |> case do
      {:ok, body} ->
        body
        |> AllocateIdsResponse.decode()
        |> Key.from_allocate_ids_proto()

      any ->
        any
    end
  end

  @spec commit(CommitRequest.t()) :: {:ok, CommitResponse.t()} | error
  @doc "Commit a transaction optionally performing any number of mutations"
  def commit(req) do
    req
    |> CommitRequest.encode()
    |> call(:commit)
    |> case do
      {:ok, body} -> {:ok, CommitResponse.decode(body)}
      any -> any
    end
  end

  @spec begin_transaction(BeginTransactionRequest.t()) ::
          {:ok, BeginTransactionResponse.t()} | error
  @doc "Begin a new transaction"
  def begin_transaction(req) do
    req
    |> BeginTransactionRequest.encode()
    |> call(:beginTransaction)
    |> case do
      {:ok, body} -> {:ok, BeginTransactionResponse.decode(body)}
      any -> any
    end
  end

  @spec rollback(RollbackRequest.t()) :: {:ok, RollbackResponse.t()} | error
  @doc "Roll back a transaction specified by a transaction id"
  def rollback(req) do
    req
    |> RollbackRequest.encode()
    |> call(:rollback)
    |> case do
      {:ok, body} -> {:ok, RollbackResponse.decode(body)}
      any -> any
    end
  end

  @spec run_query(RunQueryRequest.t()) :: list(Entity.t()) | error
  @doc "Query for entities"
  def run_query(req) do
    req
    |> RunQueryRequest.encode()
    |> call(:runQuery)
    |> case do
      {:ok, body} ->
        result = body |> RunQueryResponse.decode()

        Enum.map(result.batch.entity_results, fn e ->
          Entity.from_proto(e.entity)
        end)

      any ->
        any
    end
  end

  @spec run_query_with_pagination(RunQueryRequest.t()) :: QueryResultBatch.t() | error
  @doc "Query for entities with pagination metadata"
  def run_query_with_pagination(req) do
    req
    |> RunQueryRequest.encode()
    |> call(:runQuery)
    |> case do
      {:ok, body} ->
        body
        |> RunQueryResponse.decode()
        |> Map.get(:batch)
        |> QueryResultBatch.from_proto()

      any ->
        any
    end
  end

  @spec lookup(LookupRequest.t()) :: list(Entity.t()) | error
  @doc "Lookup entities by key"
  def lookup(req) do
    req
    |> LookupRequest.encode()
    |> call(:lookup)
    |> case do
      {:ok, body} ->
        result = body |> LookupResponse.decode()

        Enum.map(result.found, fn e ->
          Entity.from_proto(e.entity)
        end)

      any ->
        any
    end
  end

  @spec call(String.t(), method()) :: {:ok, String.t()} | error | {:error, any}
  defp call(data, method) do
    url(method)
    |> HTTPoison.post(data, [auth_header(), proto_header()])
    |> case do
      {:ok, %{body: body, status_code: code}} when code in 200..299 ->
        {:ok, body}

      {:ok, %{body: body}} ->
        {:error, Status.decode(body)}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp url(method), do: url(@api_version, method)

  defp url("v1", method) do
    Path.join([endpoint(), @api_version, "projects", "#{project()}:#{method}"])
  end

  defp endpoint, do: Application.get_env(:diplomat, :endpoint, default_endpoint(@api_version))

  defp default_endpoint("v1"), do: "https://datastore.googleapis.com"

  defp token_module, do: Application.get_env(:diplomat, :token_module, Goth.Token)

  def diplomat_account() do
   Process.get(:diplomat_account)
  end
  
  def project do
    {:ok, project_id} = case diplomat_account() do
                          nil -> Goth.Config.get(:project_id)
                          account -> Goth.Config.get(account, :project_id)
                        end
    project_id
  end

  defp api_scope, do: api_scope(@api_version)
  defp api_scope("v1"), do: "https://www.googleapis.com/auth/datastore"

  defp auth_header do
    {:ok, token} = case diplomat_account() do
                     nil -> token_module().for_scope(api_scope())
                     account -> token_module().for_scope({account, api_scope()})
                   end
    {"Authorization", "#{token.type} #{token.token}"}
  end

  defp proto_header do
    {"Content-Type", "application/x-protobuf"}
  end
end
