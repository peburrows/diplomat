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
    exclude_from_indexes: Boolean
  }

  defstruct value: nil, exclude_from_indexes: false

  @spec new(any) :: t
  def new(val),
    do: new(val, false)
    
  @spec new(any, Boolean) :: t
  def new(val=%{__struct__: struct}, exclude_from_indexes) when struct in [Diplomat.Entity, Diplomat.Key, Diplomat.Value],
    do: %__MODULE__{value: val, exclude_from_indexes: exclude_from_indexes}
  def new(val=%{__struct__: _struct}, exclude_from_indexes),
    do: new(Map.from_struct(val), exclude_from_indexes)
  def new(val, exclude_from_indexes) when is_map(val),
    do: %__MODULE__{value: Entity.new(val), exclude_from_indexes: exclude_from_indexes}
  def new(val, exclude_from_indexes) when is_list(val),
    do: %__MODULE__{value: Enum.map(val, &new/1), exclude_from_indexes: exclude_from_indexes}
  def new(val, exclude_from_indexes),
    do: %__MODULE__{value: val, exclude_from_indexes: exclude_from_indexes}

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
  @spec proto(any) :: PbVal.t
  def proto(val),
    do: proto(val, false) 
    
  # convert to protocol buffer struct
  @spec proto(any, boolean) :: PbVal.t
  def proto(nil, exclude_from_indexes),
    do: PbVal.new(value_type: {:null_value, :NULL_VALUE}, exclude_from_indexes: exclude_from_indexes)
  def proto(%__MODULE__{value: val}, exclude_from_indexes),
    do: proto(val, exclude_from_indexes)
  def proto(val, exclude_from_indexes) when is_boolean(val),
    do: PbVal.new(value_type: {:boolean_value, val}, exclude_from_indexes: exclude_from_indexes)
  def proto(val, exclude_from_indexes) when is_integer(val),
    do: PbVal.new(value_type: {:integer_value, val}, exclude_from_indexes: exclude_from_indexes)
  def proto(val, exclude_from_indexes) when is_float(val),
    do: PbVal.new(value_type: {:double_value, val}, exclude_from_indexes: exclude_from_indexes)
  def proto(val, exclude_from_indexes) when is_atom(val),
    do: val |> to_string() |> proto(exclude_from_indexes)
  def proto(val, exclude_from_indexes) when is_binary(val) do
    case String.valid?(val) do
      true -> PbVal.new(value_type: {:string_value, val}, exclude_from_indexes: exclude_from_indexes)
      false-> PbVal.new(value_type: {:blob_value, val}, exclude_from_indexes: exclude_from_indexes)
    end
  end
  def proto(val, exclude_from_indexes) when is_bitstring(val),
    do: PbVal.new(value_type: {:blob_value, val}, exclude_from_indexes: exclude_from_indexes)
  def proto(val, exclude_from_indexes) when is_list(val),
    do: proto_list(val, [], exclude_from_indexes)
  def proto(%DateTime{}=val, exclude_from_indexes) do
    timestamp = DateTime.to_unix(val, :nanoseconds)
    PbVal.new(
      value_type: {
        :timestamp_value,
        %PbTimestamp{
          seconds: div(timestamp, 1_000_000_000),
          nanos: rem(timestamp, 1_000_000_000)}
      }, exclude_from_indexes: exclude_from_indexes)
  end
  def proto(%Key{} = val, exclude_from_indexes),
    do: PbVal.new(value_type: {:key_value, Key.proto(val)}, exclude_from_indexes: exclude_from_indexes)
  def proto(%{} = val, exclude_from_indexes),
    do: PbVal.new(value_type: {:entity_value, Diplomat.Entity.proto(val), exclude_from_indexes: exclude_from_indexes})
  # might need to be more explicit about this...
  def proto({latitude, longitude}, exclude_from_indexes) when is_float(latitude) and is_float(longitude),
    do: PbVal.new(value_type: {:geo_point_value, %PbLatLng{latitude: latitude, longitude: longitude}}, exclude_from_indexes: exclude_from_indexes)

  defp proto_list([], exclude_from_indexes, acc) do
    PbVal.new(
      value_type: {
        :array_value,
        %PbArray{values: acc},
      exclude_from_indexes: exclude_from_indexes})
  end
  
  defp proto_list([head|tail], exclude_from_indexes, acc) do
    proto_list(tail, exclude_from_indexes, acc ++ [proto(head)])
  end
end
