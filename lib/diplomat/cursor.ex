defmodule Diplomat.Cursor do
  @type t :: %__MODULE__{value: String.t()}

  defstruct [:value]

  @spec new(String.t(), Keyword.t()) :: t
  def new(cursor_value, opts \\ [])
  def new(cursor_value, encode: true), do: %__MODULE__{value: encode(cursor_value)}
  def new(cursor_value, _opts), do: %__MODULE__{value: cursor_value}

  @spec encode(String.t()) :: String.t()
  def encode(cursor_value), do: Base.url_encode64(cursor_value)

  @spec decode(t | String.t()) :: String.t()
  def decode(%__MODULE__{} = cursor), do: decode(cursor.value)
  def decode(value) when is_bitstring(value), do: Base.url_decode64!(value)
end
