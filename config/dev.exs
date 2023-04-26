import Config

try do
  config :goth,
         json: "config/credentials.json" |> Path.expand |> File.read!
rescue
  _ ->
    config :goth, json: "{}"
end
