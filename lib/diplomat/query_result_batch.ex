defmodule Diplomat.QueryResultBatch do
  alias Diplomat.{Cursor, Entity}
  alias Diplomat.Proto.QueryResultBatch, as: PBQueryResultBatch

  @type t :: %__MODULE__{entity_results: [Entity.t()], end_cursor: Cursor.t() | nil}

  defstruct entity_results: [], end_cursor: nil

  @spec from_proto(PBQueryResultBatch.t()) :: t
  def from_proto(%PBQueryResultBatch{entity_results: entity_results, end_cursor: end_cursor}) do
    %__MODULE__{
      entity_results: entities_from_proto(entity_results),
      end_cursor: maybe_create_cursor(end_cursor)
    }
  end

  defp entities_from_proto(entity_results) do
    Enum.map(entity_results, &Entity.from_proto(&1.entity))
  end

  defp maybe_create_cursor(nil), do: nil
  defp maybe_create_cursor(end_cursor), do: Cursor.new(end_cursor, encode: true)
end
