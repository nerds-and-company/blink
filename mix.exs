defmodule Blink.MixProject do
  use Mix.Project

  def project do
    [
      app: :blink,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: "https://github.com/nerds-and-company/blink"
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
      {:postgrex, "~> 0.17", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Fast bulk data insertion for Ecto using PostgreSQL's COPY command.
    Blink provides a clean DSL for seeding databases with dependent tables
    and shared context.
    """
  end

  defp package do
    [
      name: "blink",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nerds-and-company/blink",
        "Changelog" => "https://github.com/nerds-and-company/blink/blob/main/CHANGELOG.md"
      },
      maintainers: ["Nerds & Company"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: "https://github.com/nerds-and-company/blink"
    ]
  end
end
