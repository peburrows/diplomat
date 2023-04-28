import Config

config :goth,
       json: "config/test-credentials.json" |> Path.expand |> File.read!

config :diplomat,
       token_module: Diplomat.TestToken
