defmodule Diplomat.Entity do
  alias Diplomat.Proto.Entity, as: PbEntity
  alias Diplomat.Proto.{CommitRequest, CommitResponse, Mutation, Mode}
  alias Diplomat.{Key, Value, Entity, Client}

  @type mutation :: {operation(), t}
  @type operation :: :insert | :upsert | :update | :delete

  @type t :: %__MODULE__{
          kind: String.t() | nil,
          key: Diplomat.Key.t() | nil,
          properties: %{optional(String.t()) => Diplomat.Value.t()}
        }

  defstruct kind: nil, key: nil, properties: %{}

  @spec new(
          props :: struct() | map(),
          kind_or_key_or_opts :: Key.t() | String.t() | Keyword.t(),
          id_or_name_or_opts :: String.t() | integer | Keyword.t(),
          opts :: Keyword.t()
        ) :: t
  @doc """
  Creates a new `Diplomat.Entity` with the given properties.

  Instead of building a `Diplomat.Enity` struct manually, `new` is the way you
  should create your entities. `new` wraps and nests properties correctly, and
  ensures that your entities have a valid `Key` (among other things).

  ## Options

    * `:exclude_from_indexes` - An atom, list of atoms, or Keyword list of
      properties that will not be indexed.
    * `:truncate` - Boolean, whether or not to truncate string values that are
      over 1500 bytes (the max length of an indexed string in Datastore).
      Defaults to `false`.
    * `:sanitize_keys` - Boolean or String. If `true`, dots (`.`) in property
      keys will be replaced with an underscore (`_`). If a string, dots will
      be replaced with the string passed. Defaults to `false`.

  ## Examples

  ### Without a key

      Entity.new(%{"foo" => "bar"})

  ### With a kind but without a name or id

      Entity.new(%{"foo" => "bar"}, "ExampleKind")

  ### With a kind and name or id

      Entity.new(%{"foo" => "bar"}, "ExampleKind", "1")

  ### With a key

      Entity.new(%{"foo" => "bar"}, Diplomat.Key.new("ExampleKind", "1"))

  ### With excluded fields

      Entity.new(%{"foo" => %{"bar" => "baz"}, "qux" => true},
                 exclude_from_indexes: [:qux, [foo: :bar]])

    The above will exclude the `:qux` field from the top level entity and the `:bar`
    field from the entity nested at `:foo`.
  """
  def new(props, kind_or_key_or_opts \\ [], id_or_opts \\ [], opts \\ [])

  def new(props = %{__struct__: _}, kind_or_key_or_opts, id_or_opts, opts),
    do: props |> Map.from_struct() |> new(kind_or_key_or_opts, id_or_opts, opts)

  def new(props, opts, [], []) when is_list(opts),
    do: %Entity{properties: value_properties(props, opts)}

  def new(props, kind, opts, []) when is_binary(kind) and is_list(opts),
    do: new(props, Key.new(kind), opts)

  def new(props, key = %Key{kind: kind}, opts, []) when is_list(opts),
    do: %Entity{kind: kind, key: key, properties: value_properties(props, opts)}

  def new(props, kind, id, opts) when is_binary(kind) and is_list(opts),
    do: new(props, Key.new(kind, id), opts)

  @spec proto(map() | t) :: Diplomat.Proto.Entity.t()
  @doc """
  Generate a `Diplomat.Proto.Entity` from a given `Diplomat.Entity`. This can
  then be used to generate the binary protocol buffer representation of the
  `Diplomat.Entity`
  """
  def proto(%Entity{key: key, properties: properties}) do
    pb_properties =
      properties
      |> Map.to_list()
      |> Enum.map(fn {name, value} ->
        {to_string(name), Value.proto(value)}
      end)

    %PbEntity{
      key: key |> Key.proto(),
      properties: pb_properties
    }
  end

  def proto(properties) when is_map(properties) do
    properties
    |> new()
    |> proto()
  end

  @spec from_proto(PbEntity.t()) :: t
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

  @spec insert([t] | t) :: [Key.t()] | Client.error()
  def insert(%Entity{} = entity), do: insert([entity])

  def insert(entities) when is_list(entities) do
    entities
    |> Enum.map(fn e -> {:insert, e} end)
    |> commit_request
    |> Diplomat.Client.commit()
    |> case do
      {:ok, resp} -> Key.from_commit_proto(resp)
      any -> any
    end
  end

  # at some point we should validate the entity keys
  @spec upsert([t] | t) :: {:ok, CommitResponse.t()} | Client.error()
  def upsert(%Entity{} = entity), do: upsert([entity])

  def upsert(entities) when is_list(entities) do
    entities
    |> Enum.map(fn e -> {:upsert, e} end)
    |> commit_request
    |> Diplomat.Client.commit()
    |> case do
      {:ok, resp} -> resp
      any -> any
    end
  end

  @spec commit_request([mutation()]) :: CommitResponse.t()
  @doc false
  def commit_request(opts), do: commit_request(opts, :NON_TRANSACTIONAL)

  @spec commit_request([mutation()], Mode.t()) :: CommitResponse.t()
  @doc false
  def commit_request(opts, mode) do
    CommitRequest.new(
      mode: mode,
      mutations: extract_mutations(opts, [])
    )
  end

  @spec commit_request([mutation()], Mode.t(), Transaction.t()) :: CommitResponse.t()
  @doc false
  def commit_request(opts, mode, trans) do
    CommitRequest.new(
      mode: mode,
      transaction_selector: {:transaction, trans.id},
      mutations: extract_mutations(opts, [])
    )
  end

  @spec extract_mutations([mutation()], [Mutation.t()]) :: [Mutation.t()]
  def extract_mutations([], acc), do: Enum.reverse(acc)

  def extract_mutations([{:insert, ent} | tail], acc) do
    extract_mutations(tail, [Mutation.new(operation: {:insert, proto(ent)}) | acc])
  end

  def extract_mutations([{:upsert, ent} | tail], acc) do
    extract_mutations(tail, [Mutation.new(operation: {:upsert, proto(ent)}) | acc])
  end

  def extract_mutations([{:update, ent} | tail], acc) do
    extract_mutations(tail, [Mutation.new(operation: {:update, proto(ent)}) | acc])
  end

  def extract_mutations([{:delete, key} | tail], acc) do
    extract_mutations(tail, [Mutation.new(operation: {:delete, Key.proto(key)}) | acc])
  end

  defp value_properties(props = %{__struct__: _struct}, opts) do
    props
    |> Map.from_struct()
    |> value_properties(opts)
  end

  defp value_properties(props, opts) when is_map(props) do
    exclude = opts |> Keyword.get(:exclude_from_indexes, []) |> get_excluded()

    props
    |> Map.to_list()
    |> Enum.map(fn {name, value} ->
      field = :"#{name}"
      exclude_field = Enum.any?(exclude, &(&1 == field))
      nested_exclude = Keyword.get(exclude, field, false)

      {
        sanitize_key(name, Keyword.get(opts, :sanitize_keys)),
        Value.new(
          value,
          sanitize_keys: Keyword.get(opts, :sanitize_keys),
          truncate: Keyword.get(opts, :truncate),
          exclude_from_indexes: exclude_field || nested_exclude
        )
      }
    end)
    |> Enum.into(%{})
  end

  defp sanitize_key(key, false), do: key |> to_string
  defp sanitize_key(key, nil), do: key |> to_string
  defp sanitize_key(key, true), do: key |> to_string |> String.replace(".", "_")
  defp sanitize_key(key, r), do: key |> to_string |> String.replace(".", r)

  defp get_excluded(fields) when is_list(fields), do: fields
  defp get_excluded(field), do: [field]

  defp values_from_proto(pb_properties) do
    pb_properties
    |> Enum.map(fn {name, pb_value} -> {name, Value.from_proto(pb_value)} end)
    |> Enum.into(%{})
  end
end
