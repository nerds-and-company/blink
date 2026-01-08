defmodule BlinkTest.Repo do
  use Ecto.Repo,
    otp_app: :blink,
    adapter: Ecto.Adapters.Postgres
end
