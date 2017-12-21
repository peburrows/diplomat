defmodule Diplomat.Value do
  alias Diplomat.Proto.Value, as: PbVal
  alias Diplomat.Proto.Key, as: PbKey
  alias Diplomat.Proto.Entity, as: PbEntity
  alias Diplomat.Proto.ArrayValue, as: PbArray
  alias Diplomat.Proto.Timestamp, as: PbTimestamp
  alias Diplomat.Proto.LatLng, as: PbLatLng
  alias Diplomat.{Entity, Key}

  @type t :: %__MODULE__{
    value: any,
    exclude_from_indexes: boolean,
  }

  defstruct value: nil, exclude_from_indexes: false

  @spec new(any, Keyword.t) :: t
  def new(val, opts \\ [])
  def new(val=%{__struct__: struct}, opts) when struct in [Diplomat.Entity, Diplomat.Key, Diplomat.Value, DateTime, NaiveDateTime],
    do: %__MODULE__{value: val, exclude_from_indexes: Keyword.get(opts, :exclude_from_indexes) == true}
  def new(val=%{__struct__: _struct}, opts),
    do: new(Map.from_struct(val), opts)
  def new(val, opts) when is_map(val),
    do: %__MODULE__{value: Entity.new(val, opts), exclude_from_indexes: Keyword.get(opts, :exclude_from_indexes) == true}
  def new(val, opts) when is_list(val),
    do: %__MODULE__{value: Enum.map(val, &(new(&1, opts))), exclude_from_indexes: Keyword.get(opts, :exclude_from_indexes) == true}

  def new(<<first::bytes-size(1500), _::bitstring>>=full, opts) do
    val =
      opts
      |> Keyword.get(:truncate)
      |> case do
           true -> first
           _ -> full
         end

    %__MODULE__{value: val, exclude_from_indexes: Keyword.get(opts, :exclude_from_indexes) == true}
  end

  def new(val, opts),
    do: %__MODULE__{value: val, exclude_from_indexes: Keyword.get(opts, :exclude_from_indexes) == true}

  @spec from_proto(PbVal.t) :: t
  def from_proto(%PbVal{value_type: {:boolean_value, val}}) when is_boolean(val),
    do: new(val)
  def from_proto(%PbVal{value_type: {:integer_value, val}}) when is_integer(val),
    do: new(val)
  def from_proto(%PbVal{value_type: {:double_value, val}}) when is_float(val),
    do: new(val)
  def from_proto(%PbVal{value_type: {:string_value, val}}),
    do: new(to_string(val))
  def from_proto(%PbVal{value_type: {:blob_value, val}}) when is_bitstring(val),
    do: new(val)
  def from_proto(%PbVal{value_type: {:key_value, %PbKey{} = val}}),
    do: val |> Diplomat.Key.from_proto |> new
  def from_proto(%PbVal{value_type: {:entity_value, %PbEntity{} = val}}),
    do: val |> Diplomat.Entity.from_proto |> new
  def from_proto(%PbVal{value_type: {:array_value, %PbArray{} = val}}) do
    %__MODULE__{value: Enum.map(val.values, &from_proto/1)}
  end
  def from_proto(%PbVal{value_type: {:timestamp_value, %PbTimestamp{} = val}}) do
    val.seconds * 1_000_000_000 + (val.nanos || 0)
    |> DateTime.from_unix!(:nanoseconds)
    |> new
  end
  def from_proto(%PbVal{value_type: {:geo_point_value, %PbLatLng{} = val}}),
    do: new({val.latitude, val.longitude})
  def from_proto(_),
    do: new(nil)

  # convert to protocol buffer struct
  @spec proto(any, Keyword.t) :: PbVal.t
  def proto(val, opts \\ [])
  def proto(%PbVal{} = val, opts) do
    %PbVal{val | exclude_from_indexes: Keyword.get(opts, :exclude_from_indexes, false)}
  end
  def proto(nil, opts),
    do: proto(PbVal.new(value_type: {:null_value, :NULL_VALUE}), opts)
  def proto(%__MODULE__{value: val, exclude_from_indexes: exclude}, opts) do
    opts = Keyword.merge(opts, [exclude_from_indexes: exclude],
                         fn (_, v1, v2) when is_list(v1) and is_list(v2) ->
                           (v1 ++ v2) |> Enum.uniq()
                         (_, v1, _) ->
                           v1
                         end)
    proto(val, opts)
  end
  def proto(val, opts) when is_boolean(val),
    do: proto(PbVal.new(value_type: {:boolean_value, val}), opts)
  def proto(val, opts) when is_integer(val),
    do: proto(PbVal.new(value_type: {:integer_value, val}), opts)
  def proto(val, opts) when is_float(val),
    do: proto(PbVal.new(value_type: {:double_value, val}), opts)
  def proto(val, opts) when is_atom(val),
    do: val |> to_string() |> proto(opts)
  def proto(val, opts) when is_binary(val) do
    case String.valid?(val) do
      true ->
        proto(PbVal.new(value_type: {:string_value, val}), opts)
      false->
        proto(PbVal.new(value_type: {:blob_value, val}), opts)
    end
  end
  def proto(val, opts) when is_bitstring(val),
    do: proto(PbVal.new(value_type: {:blob_value, val}), opts)
  def proto(val, opts) when is_list(val),
    do: proto_list(val, [], opts)
  def proto(%DateTime{}=val, opts) do
    timestamp = DateTime.to_unix(val, :nanoseconds)
    PbVal.new(
      value_type: {
        :timestamp_value,
        %PbTimestamp{
          seconds: div(timestamp, 1_000_000_000),
          nanos: rem(timestamp, 1_000_000_000)}
      }) |> proto(opts)
  end
  def proto(%Key{} = val, opts),
    do: proto(PbVal.new(value_type: {:key_value, Key.proto(val)}), opts)
  def proto(%{} = val, opts),
    do: proto(PbVal.new(value_type: {:entity_value, Diplomat.Entity.proto(val)}), opts)
  # might need to be more explicit about this...
  def proto({latitude, longitude}, opts) when is_float(latitude) and is_float(longitude),
    do: proto(PbVal.new(value_type: {:geo_point_value, %PbLatLng{latitude: latitude, longitude: longitude}}), opts)

  defp proto_list([], acc, opts) do
    PbVal.new(
      value_type: {
        :array_value,
        %PbArray{values: acc}
      }) |> proto(opts)
  end
  defp proto_list([head|tail], acc, opts) do
    proto_list(tail, acc ++ [proto(head, opts)], opts)
  end
end
