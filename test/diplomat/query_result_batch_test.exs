defmodule Diplomat.QueryResultBatchTest do
  use ExUnit.Case
  alias Diplomat.Proto.Entity, as: PbEntity
  alias Diplomat.Proto.QueryResultBatch, as: PbQueryResultBatch
  alias Diplomat.Proto.{EntityResult, Entity, PartitionId, Key, Value}
  alias Diplomat.{Cursor, Entity, QueryResultBatch}

  @query_result_batch %PbQueryResultBatch{
    end_cursor:
      <<10, 104, 10, 34, 10, 2, 105, 100, 18, 28, 26, 26, 111, 102, 102, 95, 48, 48, 48, 48, 57,
        113, 54, 49, 98, 114, 49, 77, 66, 71, 56, 49, 54, 70, 65, 109, 107, 48, 18, 62, 106, 16,
        100, 117, 102, 102, 101, 108, 45, 116, 109, 112, 45, 49, 49, 51, 51, 52, 114, 42, 11, 18,
        10, 97, 105, 114, 95, 111, 102, 102, 101, 114, 115, 34, 26, 111, 102, 102, 95, 48, 48, 48,
        48, 57, 113, 54, 49, 98, 114, 49, 77, 66, 71, 56, 49, 54, 70, 65, 109, 107, 48, 12, 24, 0,
        32, 0>>,
    entity_result_type: :PROJECTION,
    entity_results: [
      %EntityResult{
        cursor:
          <<10, 104, 10, 34, 10, 2, 105, 100, 18, 28, 26, 26, 111, 102, 102, 95, 48, 48, 48, 48,
            57, 113, 54, 49, 98, 114, 49, 77, 66, 71, 56, 49, 54, 70, 65, 109, 107, 48, 18, 62,
            106, 16, 100, 117, 102, 102, 101, 108, 45, 116, 109, 112, 45, 49, 49, 51, 51, 52, 114,
            42, 11, 18, 10, 97, 105, 114, 95, 111, 102, 102, 101, 114, 115, 34, 26, 111, 102, 102,
            95, 48, 48, 48, 48, 57, 113, 54, 49, 98, 114, 49, 77, 66, 71, 56, 49, 54, 70, 65, 109,
            107, 48, 12, 24, 0, 32, 0>>,
        entity: %PbEntity{
          key: %Key{
            partition_id: %PartitionId{
              namespace_id: nil,
              project_id: "diplomat"
            },
            path: [
              %Key.PathElement{
                id_type: {:name, "123_foo"},
                kind: "foo_table"
              }
            ]
          },
          properties: [
            {"id",
             %Value{
               exclude_from_indexes: nil,
               meaning: 18,
               value_type: {:string_value, "123_foo"}
             }}
          ]
        }
      }
    ],
    more_results: :MORE_RESULTS_AFTER_LIMIT,
    skipped_cursor: nil,
    skipped_results: nil
  }

  describe "QueryResultBatch.from_proto/1" do
    test "given a list of entity results and an end_cursor" do
      pb_query_result_batch_end_cursor = @query_result_batch.end_cursor

      assert %QueryResultBatch{
               entity_results: [%Entity{}],
               end_cursor: %Cursor{value: value}
             } = QueryResultBatch.from_proto(@query_result_batch)

      assert pb_query_result_batch_end_cursor == Cursor.decode(value)
    end
  end
end
