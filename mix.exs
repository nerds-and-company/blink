defmodule Blink.MixProject do
  use Mix.Project

  @version "0.4.1"

  def project do
    [
      app: :blink,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: "https://github.com/nerds-and-company/blink",
      dialyzer: [
        plt_core_path: "priv/plts",
        plt_local_path: "priv/plts",
        flags: [:error_handling, :underspecs]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: [
        "ecto.create --quiet -r BlinkTest.Repo",
        "ecto.migrate --quiet -r BlinkTest.Repo",
        "test"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:nimble_csv, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:postgrex, "~> 0.17", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    Fast bulk data insertion for projects using Ecto and PostgreSQL.
    Convenient syntax and easy integration with ExMachina.
    """
  end

  defp package do
    [
      name: "blink",
      files: ~w(lib guides .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nerds-and-company/blink",
        "Changelog" => "https://hexdocs.pm/blink/changelog.html"
      },
      maintainers: ["Coen Bakker"]
    ]
  end

  defp docs do
    [
      main: "getting_started",
      source_ref: "v#{@version}",
      source_url: "https://github.com/nerds-and-company/blink",
      extras: [
        "README.md",
        "guides/getting_started.md",
        "guides/using_context.md",
        "guides/loading_data_from_files.md",
        "guides/integrating_with_ex_machina.md",
        "guides/configuring_batch_size.md",
        "guides/custom_adapters.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.?/
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
