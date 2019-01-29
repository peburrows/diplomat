defmodule Diplomat.KeyUtilsTest do
  use ExUnit.Case
  alias Diplomat.{Key}

  test "KeyUtils.urlsafe" do
    app = "testbed-test"
    key_with_id1 = %Key{kind: "User", id: 1, project_id: app}
    key_with_id2 = %Key{kind: "User", id: 2, project_id: app}
    key_with_name = %Key{kind: "User", name: "hello", project_id: app}
    key_with_parent = %Key{kind: "User", id: 3, parent: key_with_id2, project_id: app}
    assert KeyUtils.urlsafe(key_with_id1) == "agx0ZXN0YmVkLXRlc3RyCgsSBFVzZXIYAQw"
    assert KeyUtils.urlsafe(key_with_id2) == "agx0ZXN0YmVkLXRlc3RyCgsSBFVzZXIYAgw"
    assert KeyUtils.urlsafe(key_with_name) == "agx0ZXN0YmVkLXRlc3RyDwsSBFVzZXIiBWhlbGxvDA"
    assert KeyUtils.urlsafe(key_with_parent) == "agx0ZXN0YmVkLXRlc3RyFAsSBFVzZXIYAgwLEgRVc2VyGAMM"
  end

  test "KeyUtils.from_urlsafe" do
    {:ok, key} = KeyUtils.from_urlsafe("agx0ZXN0YmVkLXRlc3RyGQsSBFVzZXIiBWhlbGxvDAsSBFVzZXIYAww")
    assert key.kind == "User"
    assert key.project_id == "testbed-test"
    assert key.id == 3
    assert key.parent.kind == "User"
    assert key.parent.name == "hello"
  end

  test "KeyUtils.urlsafe fail" do
    {result, _} = KeyUtils.from_urlsafe("aaaa")
    assert result == :error
  end
end
