defmodule Diplomat.Query do
  alias Diplomat.{Query, Value}
  alias Diplomat.Proto.{GqlQuery, GqlQueryParameter, RunQueryRequest, PartitionId}

  defstruct query: nil, numbered_args: [], named_args: %{}

  @type t :: %__MODULE__{
          query: String.t() | nil,
          numbered_args: args_list,
          named_args: args_map
        }

  @type args_list :: [any]
  @type args_map :: %{optional(atom) => any}

  @spec new(String.t()) :: t
  def new(query), do: new(query, [])

  @spec new(String.t(), args_map | args_list) :: t
  def new(query, args) when is_list(args) and is_binary(query) do
    %Query{
      query: query,
      numbered_args: args
    }
  end

  def new(query, args) when is_map(args) and is_binary(query) do
    %Query{
      query: query,
      named_args: args
    }
  end

  @spec proto(t) :: GqlQuery.t()
  def proto(%Query{query: q, numbered_args: num, named_args: named}) do
    GqlQuery.new(
      query_string: q,
      allow_literals: allow_literals(num, named),
      positional_bindings: positional_bindings(num),
      named_bindings: named_bindings(named)
    )
  end

  @spec execute(t, String.t() | nil) :: [Entity.t()] | Client.error()
  def execute(%__MODULE__{} = q, namespace \\ nil) do
    {:ok, project} = Goth.Config.get(:project_id)

    RunQueryRequest.new(
      query_type: {:gql_query, q |> Query.proto()},
      partition_id: PartitionId.new(namespace_id: namespace, project_id: project)
    )
    |> Diplomat.Client.run_query()
  end

  @spec positional_bindings(args_list) :: [GqlQueryParameter.t()]
  defp positional_bindings(args) do
    args
    |> Enum.map(fn i ->
      val = i |> Value.new() |> Value.proto()
      GqlQueryParameter.new(parameter_type: {:value, val})
    end)
  end

  @spec positional_bindings(args_map) :: [{String.t(), GqlQueryParameter.t()}]
  defp named_bindings(args) do
    args
    |> Enum.map(fn {k, v} ->
      val = v |> Value.new() |> Value.proto()
      {to_string(k), GqlQueryParameter.new(parameter_type: {:value, val})}
    end)
  end

  defp allow_literals([], {}), do: false
  defp allow_literals(_, _), do: true
end
