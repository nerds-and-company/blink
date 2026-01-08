import Config

if config_env() == :test do
  config :blink, BlinkTest.Repo,
    username: System.get_env("POSTGRES_USER", "postgres"),
    password: System.get_env("POSTGRES_PASSWORD", "postgres"),
    hostname: System.get_env("POSTGRES_HOST", "localhost"),
    database: "blink_test",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10

  config :blink, ecto_repos: [BlinkTest.Repo]
end
