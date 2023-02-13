defmodule FedecksClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :fedecks_client,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:websocket_client, git: "git@github.com:vtm9/websocket_client.git"},
      {:simplest_pub_sub, "~> 0.1.0"},
      {:mox, "~> 1.0", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test]},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.29.1", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description:
        "Binary websocket client that communicates with its Phoenix-based counterpart, FedecksServer. Written primarly for Nerves systems.",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/paulanthonywilson/fedecks_client"}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "CHANGELOG.md"]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
