defmodule LiveFilter.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :live_filter

  @session_options [
    store: :cookie,
    key: "_live_filter_test_key",
    signing_salt: "test_salt"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Session, @session_options)
  plug(LiveFilter.TestRouter)
end
