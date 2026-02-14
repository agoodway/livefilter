defmodule LiveFilter.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_filter,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps()
    ]
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
      quality: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "credo --strict",
        "doctor",
        "dialyzer"
      ]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:ecto, "~> 3.12"},
      {:pg_rest, github: "agoodway/pgrest"},
      {:daisy_ui_components, "~> 0.9.3"},
      {:jason, "~> 1.4"},

      # Dev/Test
      {:lazy_html, ">= 0.1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22.0", only: :dev, runtime: false}
    ]
  end
end
