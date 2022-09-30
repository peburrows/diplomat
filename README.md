[![Build Status](https://travis-ci.org/peburrows/diplomat.svg?branch=master)](https://travis-ci.org/peburrows/diplomat)

# Diplomat

Diplomat is an Elixir library for interacting with Google's Cloud Datastore.

## Installation

  1. Add datastore to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:diplomat, "~> 0.2"}]
  end
  ```

  2. Make sure you've configured [Goth](https://github.com/peburrows/goth) with your credentials:

  ```elixir
  config :goth,
    json: {:system, "GCP_CREDENTIALS_JSON"}
  ```

## Usage

#### Insert an Entity:

```elixir
Diplomat.Entity.new(
  %{"name" => "My awesome book", "author" => "Phil Burrows"},
  "Book",
  "my-unique-book-id"
) |> Diplomat.Entity.insert
```

#### Find an Entity via a GQL Query:

```elixir
Diplomat.Query.new(
  "select * from `Book` where name = @name",
  %{name: "20,000 Leagues Under The Sea"}
) |> Diplomat.Query.execute
```


#### Use multiple accounts with Diplomat
Configure Goth with additional accounts.
```elixir
{:ok, alternative_account} = Jason.decode(File.read!("priv/goth/alternative-account.json"))
Goth.Config.add_config(alternative_account)
```

Require Diplomat and use the with_account option to set current (and only current) process to use alternative process within block. 

The account name will be the client_email value from the additional Goth configuration you added by default.

```elixir
# copy data from prod to stage environment

# 1. Fetch data from production account
prod_data = Diplomat.with_account(alternative_account["client_email"]) do
  Diplomat.Query.new(
    "select * from `Book` where name = @name",
    %{name: "20,000 Leagues Under The Sea"}
  ) |> Diplomat.Query.execute
end

# 2. Write to stage/dev account (default environment)
Enum.map(prod_data, fn(entity) -> 
  Diplomat.Entity.upsert(entity)
end)
```





