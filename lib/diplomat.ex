defmodule Diplomat do
  @moduledoc """
  `Diplomat` is a library for interacting with Google's Cloud Datastore APIs.

  It provides simple interfaces for creating, updating, and deleting Entities,
  and also has support for querying via Datastore's GQL language (which is
  similar, but not exactly like, SQL).
  """
  defmodule Proto do
    use Protobuf, from: Path.expand("datastore_v1beta3.proto", __DIR__), doc: false
  end

  defmacro with_account(account, [do: block]) do
    account = Macro.expand(account, __ENV__)
    quote do
      Process.put(:diplomat_account_queue, [unquote(account)] ++ Process.get(:diplomat_account_queue, []))
      Process.put(:diplomat_account, unquote(account))
      diplomat__response = (unquote(block))
      diplomat__account_queue = case Process.get(:diplomat_account_queue, []) do
                                  [_|t] -> t
                                  _ -> []
                                end
      Process.put(:diplomat_account_queue, diplomat__account_queue)
      Process.put(:diplomat_account, List.first(diplomat__account_queue))
      diplomat__response
    end
  end
  
end
