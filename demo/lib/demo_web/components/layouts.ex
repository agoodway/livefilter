defmodule DemoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DemoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <header class="border-b border-base-200 bg-base-100/80 backdrop-blur-sm sticky top-0 z-50">
        <div class="lf-container">
          <div class="flex items-center justify-between h-16">
            <div class="flex items-center gap-8">
              <a href="/" class="lf-brand">
                <div class="lf-brand-icon">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    class="size-5"
                  >
                    <line x1="4" y1="6" x2="20" y2="6" />
                    <circle cx="8" cy="6" r="2" fill="currentColor" />
                    <line x1="4" y1="12" x2="20" y2="12" />
                    <circle cx="16" cy="12" r="2" fill="currentColor" />
                    <line x1="4" y1="18" x2="20" y2="18" />
                    <circle cx="11" cy="18" r="2" fill="currentColor" />
                  </svg>
                </div>
                <span class="lf-brand-text">LiveFilter</span>
              </a>
              <nav class="hidden md:flex items-center gap-1">
                <a
                  href="https://github.com/agoodway/livefilter"
                  target="_blank"
                  class="px-3 py-2 rounded-lg text-sm font-medium text-base-content/60 hover:text-base-content hover:bg-base-200 transition-colors"
                >
                  Docs
                </a>
              </nav>
            </div>
            <div class="flex items-center gap-3">
              <a
                href="https://github.com/agoodway/livefilter"
                target="_blank"
                class="btn btn-ghost btn-sm gap-2"
              >
                <.icon name="hero-code-bracket" class="size-4" />
                <span class="hidden sm:inline">GitHub</span>
              </a>
              <.theme_toggle />
            </div>
          </div>
        </div>
      </header>

      <main class="lf-container py-8">
        {render_slot(@inner_block)}
      </main>

      <footer class="border-t border-base-200 py-6 mt-8">
        <div class="lf-container">
          <p class="text-center text-sm text-base-content/60">
            A project by
            <a
              href="https://goodway.dev"
              target="_blank"
              class="font-medium text-primary hover:underline"
            >
              Goodway
            </a>
            — we build software that drives results.
          </p>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
