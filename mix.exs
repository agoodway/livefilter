defmodule LiveFilter.MixProject do
  use Mix.Project

  @version "0.1.8"
  @source_url "https://github.com/agoodway/livefilter"

  def project do
    [
      app: :livefilter,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      description: description(),
      package: package(),
      name: "LiveFilter",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: [quality: :test]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      # `ex_dna --max-clones 2` allows the two `attr` declaration blocks
      # shared between Phoenix.Component LiveComponents (boolean/async_select
      # and select/multi_select). Extracting them via macro hurts readability
      # for trivial gain. Drop to 0 if/when those are addressed.
      quality: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "sobelow --config",
        "ex_dna --max-clones 2",
        "doctor",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:ecto, "~> 3.12"},
      {:pgrest, "~> 0.1.0"},
      # {:pgrest, path: "../pgrest"},
      {:daisy_ui_components, "~> 0.9.3"},
      {:jason, "~> 1.4"},

      # Dev/Test
      {:lazy_html, ">= 0.1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.3", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Composable, URL-driven filtering for Phoenix LiveView with Linear/Notion-style filters and PostgREST-compatible parameters."
  end

  defp package do
    [
      maintainers: ["Chase Pursley"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
