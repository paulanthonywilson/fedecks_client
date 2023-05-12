defmodule FedecksClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :fedecks_client,
      version: "0.1.3",
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
      {:mint_web_socket, "~> 1.0"},
      {:simplest_pub_sub, "~> 0.1.0"},
      {:mox, "~> 1.0", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test]},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.29.1", only: :dev, runtime: false},

      # For setting up a Fedecks server in tests
      {:phoenix, "~> 1.7.0-rc.3", only: :test, override: true},
      {:plug_cowboy, "~> 2.5", only: :test},
      {:fedecks_server, git: "git@github.com:paulanthonywilson/fedecks_server.git", only: :test},
      {:recon, "~> 2.5", only: [:dev, :test]},
      {:castore, "~> 1.0", only: [:dev, :test]}
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

  defp elixirc_paths(:test), do: ["lib", "example", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "example"]
  defp elixirc_paths(_), do: ["lib"]
end
