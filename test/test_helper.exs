Application.put_env(:live_filter, LiveFilter.TestEndpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("test_secret", 8),
  live_view: [signing_salt: "test_live_view_salt"],
  server: false
)

{:ok, _} = LiveFilter.TestEndpoint.start_link()

ExUnit.start()
