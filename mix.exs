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
      aliases: aliases()
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
      {:postgrex, "~> 0.17", only: :test}
    ]
  end
end
