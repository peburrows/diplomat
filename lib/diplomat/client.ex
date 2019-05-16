defmodule Diplomat.Client do
  alias Diplomat.{Entity, Key}

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
  def allocate_ids(req, project_id \\ nil) do
    req
    |> AllocateIdsRequest.encode()
    |> call(:allocateIds, project_id)
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
  def commit(req, project_id \\ nil) do
    req
    |> CommitRequest.encode()
    |> call(:commit, project_id)
    |> case do
      {:ok, body} -> {:ok, CommitResponse.decode(body)}
      any -> any
    end
  end

  @spec begin_transaction(BeginTransactionRequest.t()) ::
          {:ok, BeginTransactionResponse.t()} | error
  @doc "Begin a new transaction"
  def begin_transaction(req, project_id \\ nil) do
    req
    |> BeginTransactionRequest.encode()
    |> call(:beginTransaction, project_id)
    |> case do
      {:ok, body} -> {:ok, BeginTransactionResponse.decode(body)}
      any -> any
    end
  end

  @spec rollback(RollbackRequest.t()) :: {:ok, RollbackResponse.t()} | error
  @doc "Roll back a transaction specified by a transaction id"
  def rollback(req, project_id \\ nil) do
    req
    |> RollbackRequest.encode()
    |> call(:rollback, project_id)
    |> case do
      {:ok, body} -> {:ok, RollbackResponse.decode(body)}
      any -> any
    end
  end

  @spec run_query(RunQueryRequest.t()) :: list(Entity.t()) | error
  @doc "Query for entities"
  def run_query(req, project_id \\ nil) do
    req
    |> RunQueryRequest.encode()
    |> call(:runQuery, project_id)
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

  @spec lookup(LookupRequest.t()) :: list(Entity.t()) | error
  @doc "Lookup entities by key"
  def lookup(req, project_id \\ nil) do
    req
    |> LookupRequest.encode()
    |> call(:lookup, project_id)
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
  defp call(data, method, project_id \\ nil) do
    url(method, project_id)
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

  defp url(method, project_id \\ nil), do: url1(@api_version, method, project_id)

  defp url1("v1", method, project_id \\ nil) do
    Path.join([endpoint(), @api_version, "projects", "#{project(project_id)}:#{method}"])
  end

  defp endpoint, do: Application.get_env(:diplomat, :endpoint, default_endpoint(@api_version))

  defp default_endpoint("v1"), do: "https://datastore.googleapis.com"

  defp token_module, do: Application.get_env(:diplomat, :token_module, Goth.Token)

  defp project(project_id \\ nil) do
    if !is_nil(project_id) && String.length(project_id) > 0 do
      project_id
    else
      {:ok, project_id} = Goth.Config.get(:project_id)
      project_id
    end
  end

  defp api_scope, do: api_scope(@api_version)
  defp api_scope("v1"), do: "https://www.googleapis.com/auth/datastore"

  defp auth_header do
    {:ok, token} = token_module().for_scope(api_scope())
    {"Authorization", "#{token.type} #{token.token}"}
  end

  defp proto_header do
    {"Content-Type", "application/x-protobuf"}
  end
end
