defmodule Blink.RealPoolTest do
  # Why not the SQL Sandbox like every other test: the sandbox funnels every
  # collaborating process onto the owner's single connection, so parallel COPYs
  # enroll in the test transaction and roll back with it — atomicity appears to
  # hold no matter what the code does. Only a real pool, where each task checks
  # out its own connection, can tell a genuine single-connection transaction
  # from an accidental one. (v0.7.0 wrapped parallel COPYs in a transaction
  # that never covered them; every sandboxed test passed anyway.) These tests
  # commit real rows, hence async: false and the truncation on the way out.
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false

  alias BlinkTest.PoolRepo

  @moduletag capture_log: true

  setup do
    config = Application.get_env(:blink, BlinkTest.Repo) |> Keyword.delete(:pool)
    start_supervised!({PoolRepo, config})
    truncate_via_pool_repo()

    # Supervised children are stopped before on_exit runs, so the committed
    # rows are removed through the sandbox repo on a raw (sandbox: false)
    # connection.
    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(BlinkTest.Repo, sandbox: false)
      # on_exit runs outside capture_log, so keep this query quiet.
      BlinkTest.Repo.query!("TRUNCATE posts, users CASCADE", [], log: false)
    end)

    :ok
  end

  test "atomic: true rolls back every table when a later table fails" do
    assert_raise Postgrex.Error, fn ->
      Blink.Seeder.run(failing_seeder(), PoolRepo, atomic: true, batch_size: 20)
    end

    assert count("users") == 0
    assert count("posts") == 0
  end

  test "atomic: false commits earlier tables and raises in the calling process" do
    # The raise itself is part of the regression: in v0.7.0 a failed parallel
    # COPY killed the caller through the task link instead of raising.
    assert_raise Postgrex.Error, fn ->
      Blink.Seeder.run(failing_seeder(), PoolRepo, atomic: false, batch_size: 20)
    end

    assert count("users") == 100
    assert count("posts") == 0
  end

  test "restores the caller's statement_timeout after an atomic copy" do
    {:ok, {prior, current}} =
      PoolRepo.transaction(fn ->
        prior = PoolRepo.query!("SHOW statement_timeout").rows

        :ok =
          Blink.copy_to_table([%{id: 1, name: "A", email: "a@x"}], "users", PoolRepo,
            atomic: true
          )

        {prior, PoolRepo.query!("SHOW statement_timeout").rows}
      end)

    assert current == prior
  end

  defp failing_seeder do
    Blink.Seeder.new()
    |> Blink.Seeder.with_table("users", fn _, _ ->
      for i <- 1..100, do: %{id: i, name: "User #{i}", email: "u#{i}@example.com"}
    end)
    |> Blink.Seeder.with_table("posts", fn _, _ ->
      # user_id 999_999 has no matching user, so the posts COPY fails after
      # the users batches have been copied.
      [%{id: 1, title: "T", body: "B", user_id: 999_999}]
    end)
  end

  defp truncate_via_pool_repo do
    PoolRepo.query!("TRUNCATE posts, users CASCADE")
  end

  defp count(table) do
    PoolRepo.one(from(r in table, select: count()))
  end
end
