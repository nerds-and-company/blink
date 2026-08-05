defmodule BlinkTest.PoolRepo do
  @moduledoc """
  A repo with a regular connection pool instead of the SQL Sandbox, for tests
  that assert cross-connection transaction semantics. Started per-test; see
  `Blink.RealPoolTest`.
  """
  use Ecto.Repo,
    otp_app: :blink,
    adapter: Ecto.Adapters.Postgres
end
