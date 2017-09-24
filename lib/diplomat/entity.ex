defmodule Diplomat.Entity do
  alias Diplomat.Proto.Entity, as: PbEntity
  alias Diplomat.Proto.{CommitRequest, CommitResponse, Mutation, Mode}
  alias Diplomat.{Key, Value, Entity, Client}

  @type mutation :: {operation(), t}
  @type operation :: :insert | :upsert | :update | :delete

  @type t :: %__MODULE__{
    kind: String.t | nil,
    key:  Diplomat.Key.t | nil,
    properties: %{optional(String.t) => Diplomat.Value.t},
    exclude_from_indexes: List
  }

  defstruct kind: nil, key: nil, properties: %{}, exclude_from_indexes: []

  @spec new(struct() | map()) :: t
  @doc """
  Creates a new `Diplomat.Entity` with the given properties.

  Instead of building a `Diplomat.Enity` struct manually, `new` is the way you
  should create your entities. `new` wraps and nests properties correctly, and
  ensures that your entities have a valid `Key` (among other things).
  """
  def new(props = %{__struct__: _struct}),
    do: Map.from_struct(props) |> new()
  def new(props) when is_map(props),
    do: %Entity{properties: value_properties(props)}

  @spec new(struct() | map(), Key.t | String.t) :: t
  @doc """
  Creates a new `Diplomat.Entity` with the given properties and `Diplomat.Key` or `kind`
  """
  def new(props, kind) when is_binary(kind),
    do: new(props, Key.new(kind))
  def new(props = %{__struct__: _struct}, key),
    do: new(Map.from_struct(props), key)
  def new(props, %Key{kind: kind} = key) when is_map(props) do
    %Entity{
      kind: kind,
      key:  key,
      properties: value_properties(props),
    }
  end
  def new(props, %Key{kind: kind} = key, exclude_from_indexes) when is_map(props) do
    %Entity{
      kind: kind,
      key:  key,
      properties: value_properties(props),
      exclude_from_indexes: exclude_from_indexes
    }
  end

  @spec new(struct() | map(), String.t, String.t | integer()) :: t
  @doc """
  Creates a new `Diplomat.Entity` with the given properties and creates a
  `Diplomat.Key` with `kind` and `id`.
  """
  def new(props, kind, id),
    do: new(props, Key.new(kind, id))
    
  @spec new(struct() | map(), String.t, String.t | integer(), List) :: t
  @doc """
  Creates a new `Diplomat.Entity` with the given properties and creates a
  `Diplomat.Key` with `kind` and `id` and `exclude_from_indexes`'.
  """
  def new(props, kind, id, exclude_from_indexes),
    do: new(props, Key.new(kind, id), exclude_from_indexes)

  @spec proto(map() | t) :: Diplomat.Proto.Entity.t
  @doc """
  Generate a `Diplomat.Proto.Entity` from a given `Diplomat.Entity`. This can
  then be used to generate the binary protocol buffer representation of the
  `Diplomat.Entity`
  """
  def proto(%Entity{key: key, properties: properties, exclude_from_indexes: exclude_from_indexes}) do
    pb_properties =
      properties
      |> Map.to_list
      |> Enum.map(fn {name, value} ->
        exclude = (name in exclude_from_indexes)
        {to_string(name), Value.proto(value, exclude)}
      end)

    %PbEntity{
      key: key |> Key.proto,
      properties: pb_properties
    }
  end
  def proto(properties) when is_map(properties) do
    properties
    |> new()
    |> proto()
  end

  @spec from_proto(PbEntity.t) :: t
  @doc "Create a `Diplomat.Entity` from a `Diplomat.Proto.Entity`"
  def from_proto(%PbEntity{key: nil, properties: pb_properties}),
    do: %Entity{properties: values_from_proto(pb_properties)}
  def from_proto(%PbEntity{key: pb_key, properties: pb_properties}) do
    key = Key.from_proto(pb_key)
    %Entity{
      kind: key.kind,
      key: key,
      properties: values_from_proto(pb_properties)
    }
  end

  @spec properties(t) :: map()
  @doc """
  Extract a `Diplomat.Entity`'s properties as a map.

  The properties are stored on the struct as a map string keys and
  `Diplomat.Value` values. This function will allow you to extract the properties
  as a map with string keys and Elixir built-in values.

  For example, creating an `Entity` looks like the following:
  ```
  iex> entity = Entity.new(%{"hello" => "world"})
  # =>   %Diplomat.Entity{key: nil, kind: nil,
  #         properties: %{"hello" => %Diplomat.Value{value: "world"}}}
  ```

  `Diplomat.Entity.properties/1` allows you to extract those properties to get
  the following: `%{"hello" => "world"}`
  """
  def properties(%Entity{properties: properties}) do
    properties
    |> Enum.map(fn {key, value} ->
      {key, value |> recurse_properties}
    end)
    |> Enum.into(%{})
  end
  defp recurse_properties(value) do
    case value do
      %Entity{} -> value |> properties
      %Value{value: value} -> value |> recurse_properties
      value when is_list(value) -> value |> Enum.map(&recurse_properties/1)
      _ -> value
    end
  end

  @spec insert([t] | t) :: {:ok, Key.t} | Client.error()
  def insert(%Entity{}=entity), do: insert([entity])
  def insert(entities) when is_list(entities) do
    entities
    |> Enum.map(fn(e)-> {:insert, e} end)
    |> commit_request
    |> Diplomat.Client.commit
    |> case do
      {:ok, resp} -> Key.from_commit_proto(resp)
      any -> any
    end
  end

  # at some point we should validate the entity keys
  @spec upsert([t] | t) :: {:ok, CommitResponse.t} | Client.error()
  def upsert(%Entity{}=entity), do: upsert([entity])
  def upsert(entities) when is_list(entities) do
    entities
    |> Enum.map(fn(e)-> {:upsert, e} end)
    |> commit_request
    |> Diplomat.Client.commit
    |> case do
      {:ok, resp} -> resp
      any -> any
    end
  end

  @spec commit_request([mutation()]) :: CommitResponse.t
  @doc false
  def commit_request(opts), do: commit_request(opts, :NON_TRANSACTIONAL)

  @spec commit_request([mutation()], Mode.t) :: CommitResponse.t
  @doc false
  def commit_request(opts, mode) do
    CommitRequest.new(
      mode: mode,
      mutations: extract_mutations(opts, [])
    )
  end

  @spec commit_request([mutation()], Mode.t, Transaction.t) :: CommitResponse.t
  @doc false
  def commit_request(opts, mode, trans) do
    CommitRequest.new(
      mode: mode,
      transaction_selector: {:transaction, trans.id},
      mutations: extract_mutations(opts, [])
    )
  end

  @spec extract_mutations([mutation()], [Mutation.t]) :: [Mutation.t]
  def extract_mutations([], acc), do: Enum.reverse(acc)
  def extract_mutations([{:insert, ent}|tail], acc) do
    extract_mutations(tail, [Mutation.new(operation: {:insert, proto(ent)})|acc])
  end
  def extract_mutations([{:upsert, ent}|tail], acc) do
    extract_mutations(tail, [Mutation.new(operation: {:upsert, proto(ent)})|acc])
  end
  def extract_mutations([{:update, ent}|tail], acc) do
    extract_mutations(tail, [Mutation.new(operation: {:update, proto(ent)})|acc])
  end
  def extract_mutations([{:delete, key}|tail], acc) do
    extract_mutations(tail, [Mutation.new(operation: {:delete, Key.proto(key)})|acc])
  end

  defp value_properties(props = %{__struct__: _struct}) do
    props
    |> Map.from_struct()
    |> value_properties()
  end
  defp value_properties(props) when is_map(props) do
    props
    |> Map.to_list
    |> Enum.map(fn {name, value} -> {to_string(name), Value.new(value)} end)
    |> Enum.into(%{})
  end

  defp values_from_proto(pb_properties) do
    pb_properties
    |> Enum.map(fn {name, pb_value} -> {name, Value.from_proto(pb_value)} end)
    |> Enum.into(%{})
  end
end
