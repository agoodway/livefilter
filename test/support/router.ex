defmodule LiveFilter.TestRouter do
  @moduledoc false
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
  end

  scope "/", LiveFilter do
    pipe_through(:browser)
    live("/test", TestLive)
  end
end
