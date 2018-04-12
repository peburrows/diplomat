defmodule Diplomat.Transaction do
  @moduledoc """
  ```
  Transaction.begin
  |> Transaction.save(entity)
  |> Transaction.save(entity2)
  |> Transaction.commit
  ```

  OR

  ```
  Transaction.begin fn t ->
    # auto-begin
    t
    |> Transaction.save(entity)
    |> Transaction.save(entity2)
    # auto-commits on exit
  end
  ```
  """

  alias Diplomat.Proto.BeginTransactionResponse, as: TransResponse
  alias Diplomat.Proto.BeginTransactionRequest,  as: TransRequest
  alias Diplomat.Proto.{
    CommitRequest, CommitResponse,
    RollbackRequest, RollbackResponse,
    LookupRequest, ReadOptions
  }
  alias Diplomat.{Transaction, Entity, Key, Client}

  @type t :: %__MODULE__{
    id: integer,
    state: :init | :begun,
    mutations: [Entity.mutation],
  }

  defstruct id: nil, state: :init, mutations: []

  @spec from_begin_response(TransResponse.t) :: t
  def from_begin_response(%TransResponse{transaction: id}) do
    %Transaction{id: id, state: :begun}
  end

  @spec begin() :: t | Client.error
  def begin do
    TransRequest.new
    |> Diplomat.Client.begin_transaction
    |> case do
         {:ok, resp} ->
           resp |> Transaction.from_begin_response
         other ->
           other
       end
  end

  @spec begin((() -> t)) :: {:ok, CommitResponse.t} | Client.error | {:error, any}
  def begin(block) when is_function(block) do
    # the try block defines a new scope that isn't accessible in the rescue block
    # so we need to begin the transaction here so both have access to the var
    transaction = begin()
    try do
      transaction
      |> block.()
      |> commit
    rescue
      e ->
        rollback(transaction)
        {:error, e}
    end
  end

  @spec commit(t) :: {:ok, CommitResponse.t} | Client.error
  def commit(%Transaction{}=transaction) do
    transaction
    |> to_commit_proto
    |> Diplomat.Client.commit
  end

  # require the transaction to have an ID
  @spec rollback(t) :: {:ok, RollbackResponse.t} | Client.error
  def rollback(%Transaction{id: id}) when not is_nil(id) do
    RollbackRequest.new(transaction: id)
    |> Diplomat.Client.rollback
  end

  # handle the case where we attempt to rollback something that isn't a transaction
  # this should only happen when beginning a transaction fails
  def rollback(t), do: t

  @spec find(Transaction.t, Key.t | [Key.t]) :: list(Entity.t) | Client.error
  def find(%Transaction{id: id}, keys) when is_list(keys) do
    %LookupRequest {
      keys: Enum.map(keys, &Key.proto(&1)),
      read_options: %ReadOptions{consistency_type: {:transaction, id}}
    } |> Diplomat.Client.lookup
  end
  def find(transaction, key) do
    find(transaction, [key])
  end

  # we could clean this up with some macros
  @spec insert(t, Entity.t | [Entity.t]) :: t
  def insert(%Transaction{}=t, %Entity{}=e), do: insert(t, [e])
  def insert(%Transaction{}=t, []), do: t
  def insert(%Transaction{}=t, [%Entity{}=e | tail]) do
    insert(%{t | mutations: [{:insert, e} | t.mutations]}, tail)
  end

  @spec upsert(t, Entity.t | [Entity.t]) :: t
  def upsert(%Transaction{}=t, %Entity{}=e), do: upsert(t, [e])
  def upsert(%Transaction{}=t, []), do: t
  def upsert(%Transaction{}=t, [%Entity{}=e | tail]) do
    upsert(%{t | mutations: [{:upsert, e} | t.mutations]}, tail)
  end

  @spec update(t, Entity.t | [Entity.t]) :: t
  def update(%Transaction{}=t, %Entity{}=e), do: update(t, [e])
  def update(%Transaction{}=t, []), do: t
  def update(%Transaction{}=t, [%Entity{}=e | tail]) do
    update(%{t | mutations: [{:update, e} | t.mutations]}, tail)
  end

  @spec delete(t, Key.t | [Key.t]) :: t
  def delete(%Transaction{}=t, %Key{}=k), do: delete(t, [k])
  def delete(%Transaction{}=t, []), do: t
  def delete(%Transaction{}=t, [%Key{}=k | tail]) do
    delete(%{t | mutations: [{:delete, k} | t.mutations]}, tail)
  end

  @spec to_commit_proto(t) :: CommitRequest.t
  def to_commit_proto(%Transaction{}=transaction) do
    CommitRequest.new(
      mode: :TRANSACTIONAL,
      transaction_selector: {:transaction, transaction.id},
      mutations: Entity.extract_mutations(transaction.mutations, [])
    )
  end
end
