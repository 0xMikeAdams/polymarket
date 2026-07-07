defmodule Polymarket.MixProject do
  use Mix.Project

  def project do
    [
      app: :polymarket,
      version: "0.4.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description:
        "Elixir client for Polymarket APIs (Gamma, Data, CLOB) with EIP-712 order signing " <>
          "and realtime WebSocket streaming via PolyNode",
      package: package(),
      name: "Polymarket",
      source_url: "https://github.com/mikeadams/polymarket",
      homepage_url: "https://github.com/mikeadams/polymarket",
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.4"},
      {:jason, "~> 1.4"},
      {:eip712, "~> 0.2.0"},
      {:fresh, "~> 0.4.4"},
      {:plug, "~> 1.16", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:bandit, "~> 1.0", only: :test},
      {:websock_adapter, "~> 0.5", only: :test},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "polymarket",
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE),
      maintainers: ["Mike Adams"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/mikeadams/polymarket"
      }
    ]
  end
end
