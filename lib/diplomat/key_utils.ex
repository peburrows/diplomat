defmodule KeyUtils do
  use Bitwise
  alias Diplomat.Key

  @spec urlsafe(Key.t()) :: String.t()
  def urlsafe(%Key{} = key) do
    key
    |> encode
    |> Base.url_encode64(padding: false)
  end

  @spec from_urlsafe(bitstring) :: {:ok, Key.t()} | {:error, String.t()}
  def from_urlsafe(value) when is_bitstring(value) do
    key =
      value
      |> Base.url_decode64!(padding: false)
      |> decode

    {:ok, key}
  rescue
    _ -> {:error, "Invalid data"}
  end

  #############################################################################
  # PRIVATE FUNCTIONS
  #############################################################################

  # encode function

  defp encode(%Key{} = key) do
    result =
      put_int(106) <>
        put_prefix_string(key.project_id) <>
        put_int(114) <> put_int(path_byte_size(key)) <> encode(Key.path(key))

    if key.namespace do
      result <> put_int(162) <> put_prefix_string(key.namespace)
    else
      result
    end
  end

  defp encode([_head | _tail] = list) do
    list
    |> Enum.map(&encode_path_item(&1))
    |> Enum.reduce(<<>>, &(&2 <> &1))
  end

  defp encode_path_item([kind, id]) when is_integer(id) do
    put_int(11) <>
      put_int(18) <> put_prefix_string(kind) <> put_int(24) <> put_int_64(id) <> put_int(12)
  end

  defp encode_path_item([kind, name]) when is_bitstring(name) do
    put_int(11) <>
      put_int(18) <>
      put_prefix_string(kind) <> put_int(34) <> put_prefix_string(name) <> put_int(12)
  end

  defp put_int(v) when is_integer(v) do
    if (v &&& 127) == v do
      <<v>>
    else
      do_put_int(v, <<>>)
    end
  end

  defp put_int_64(v) when is_integer(v) do
    do_put_int(v, <<>>)
  end

  defp do_put_int(0, acc) do
    acc
  end

  defp do_put_int(v, acc) when v < 0 do
    do_put_int((v + 1) <<< 64, acc)
  end

  defp do_put_int(v, acc) do
    next_v = v >>> 7
    next_bit = v &&& 127

    if next_v > 0 do
      do_put_int(next_v, acc <> <<next_bit ||| 128>>)
    else
      acc <> <<next_bit>>
    end
  end

  defp put_prefix_string(v) when is_bitstring(v) do
    put_int(String.length(v)) <> v
  end

  # decode functions

  defp decode(data) do
    {106, data} = get_int(data)
    {project_id, data} = get_prefix_string(data)
    {114, data} = get_int(data)
    {path_size, data} = get_int(data)
    <<path_data::binary-size(path_size), left::binary>> = data
    key = path_data |> decode_path([]) |> Key.from_path()

    if left == "" do
      %{key | project_id: project_id}
    else
      {162, data} = get_int(left)
      {namespace, _data} = get_prefix_string(data)
      %{key | project_id: project_id, namespace: namespace}
    end
  end

  defp decode_path(<<>>, path) do
    path
  end

  defp decode_path(data, path) do
    {11, data} = get_int(data)
    {18, data} = get_int(data)
    {kind, data} = get_prefix_string(data)
    {value, data} = get_int(data)

    case value do
      24 ->
        {id, data} = get_int_64(data)
        {12, data} = get_int(data)
        decode_path(data, path ++ [[kind, id]])

      34 ->
        {name, data} = get_prefix_string(data)
        {12, data} = get_int(data)
        decode_path(data, path ++ [[kind, name]])
    end
  end

  defp get_int(<<b::8, data::bitstring>>) do
    if (b &&& 128) == 0 do
      {b, data}
    else
      {result, next_data} = do_get_int(data, b, 0, 0)

      result =
        if result > 1 <<< 63 do
          result - (1 <<< 64)
        else
          result
        end

      {result, next_data}
    end
  end

  defp do_get_int(data, b, shift, result) do
    result = result ||| (b &&& 127) <<< shift
    shift = shift + 7

    if (b &&& 128) == 0 do
      {result, data}
    else
      <<next_b::8, next_data::bitstring>> = data
      do_get_int(next_data, next_b, shift, result)
    end
  end

  defp get_int_64(data) do
    {result, next_data} = do_get_int_64(data, 0, 0)

    result =
      if result > 1 <<< 63 do
        result - (1 <<< 64)
      else
        result
      end

    {result, next_data}
  end

  defp do_get_int_64(<<b::8, next_data::bitstring>>, result, shift) do
    result = result ||| (b &&& 127) <<< shift

    if (b &&& 128) == 0 do
      {result, next_data}
    else
      do_get_int_64(next_data, result, shift + 7)
    end
  end

  defp get_prefix_string(data) do
    {size, left_data} = get_int(data)
    <<result::binary-size(size), bin::binary>> = left_data
    {result, bin}
  end

  # get size functions

  defp path_byte_size(%Key{} = key) do
    key
    |> Key.path()
    |> Enum.map(&path_item_byte_size(&1))
    |> Enum.reduce(0, &(&1 + &2))
  end

  defp path_item_byte_size([kind, id]) when is_integer(id) do
    length_string(String.length(kind)) + length_var_int_64(id) + 4
  end

  defp path_item_byte_size([kind, name]) when is_bitstring(name) do
    length_string(String.length(kind)) + length_string(String.length(name)) + 4
  end

  defp length_string(v), do: length_var_int_64(v) + v

  defp length_var_int_64(v) when v < 0, do: 10
  defp length_var_int_64(v), do: do_length_var_int_64(v, 0)

  defp do_length_var_int_64(0, acc), do: acc
  defp do_length_var_int_64(v, acc), do: do_length_var_int_64(v >>> 7, acc + 1)
end
