defmodule Diplomat.Entity.AllocateIdsTest do
  use ExUnit.Case
  alias Diplomat.Key
  alias Diplomat.Proto.AllocateIdsResponse, as: PbAllocateResp

  setup do
    bypass = Bypass.open()
    Application.put_env(:diplomat, :endpoint, "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass}
  end

  test "generating keys from an AllocateIdsResponse" do
    keys =
      PbAllocateResp.new(
        keys: [
          Key.new("Log", 1) |> Key.proto(),
          Key.new("Log", 2) |> Key.proto(),
          Key.new("Log", 3) |> Key.proto()
        ]
      )
      |> Key.from_allocate_ids_proto()

    assert Enum.count(keys) == 3

    Enum.each(keys, fn k ->
      assert k.name == nil
      assert k.kind == "Log"
      refute k.id == nil
    end)
  end

  test "allocating ids", %{bypass: bypass} do
    count = 20
    kind = "Log"
    {:ok, project} = Goth.Config.get(:project_id)

    Bypass.expect(bypass, fn conn ->
      assert Regex.match?(~r{/v1/projects/#{project}:allocateIds}, conn.request_path)

      keys =
        Enum.map(1..count, fn i ->
          Key.new(kind, i) |> Key.proto()
        end)

      resp = PbAllocateResp.new(keys: keys) |> PbAllocateResp.encode()
      Plug.Conn.resp(conn, 201, resp)
    end)

    # we should get back a bunch of keys, I believe
    keys = Key.allocate_ids(kind, count)
    assert Enum.count(keys) == count

    Enum.each(keys, fn k ->
      refute k.id == nil
      assert k.kind == kind
      assert k.name == nil
    end)
  end
end
