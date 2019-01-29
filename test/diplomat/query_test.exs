defmodule Diplomat.QueryTest do
  use ExUnit.Case
  alias Diplomat.{Query, Value}
  alias Diplomat.Proto.{GqlQuery, GqlQueryParameter}

  test "we can construct a query" do
    q = "select * from Assets where title = @1"
    title = "20,000 Leagues Under The Sea"
    query = Query.new(q, [title])
    assert %Query{query: ^q, numbered_args: [^title]} = query
  end

  test "we can convert a Query to a Proto.GqlQuery" do
    query = "select * from whatever where yes = @1"
    arg = "sure"
    arg_val = Value.new(arg) |> Value.proto()

    assert %GqlQuery{
             query_string: ^query,
             allow_literals: true,
             positional_bindings: [%GqlQueryParameter{parameter_type: {:value, ^arg_val}}],
             named_bindings: []
           } = Query.new(query, [arg]) |> Query.proto()

    assert <<_::binary>> = Query.new(query, [arg]) |> Query.proto() |> GqlQuery.encode()
  end

  test "we can construct a query with named args" do
    {q, args} = {"select * from Log where user = @user", %{user: "phil"}}
    query = Query.new(q, args)
    assert %Query{query: ^q, named_args: ^args} = query
  end

  test "that atom keys in named arg maps are converted to strings" do
    {q, args} = {"select @what", %{what: "sure"}}
    query = Query.new(q, args)
    val = "sure" |> Value.proto()

    assert %GqlQuery{
             named_bindings: [
               {"what", %GqlQueryParameter{parameter_type: {:value, ^val}}}
             ]
           } = query |> Query.proto()
  end

  test "we can convert a Query with named args to a Proto.GqlQuery" do
    {q, args} = {"select * from whatever where thing = @thing", %{thing: "me"}}
    query = Query.new(q, args)
    assert <<_::binary>> = query |> Query.proto() |> GqlQuery.encode()
  end
end
