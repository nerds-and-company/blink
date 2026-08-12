defmodule Blink.TruncateTest do
  # async: false — TRUNCATE takes ACCESS EXCLUSIVE locks, which would block
  # behind (and block) concurrent sandboxed tests touching the same tables.
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false

  alias BlinkTest.Repo

  @moduletag capture_log: true

  defmodule NoTruncateAdapter do
    @behaviour Blink.Adapter

    @impl true
    def call(_rows, _table_name, _repo, _opts), do: :ok
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp users_and_posts_seeder do
    Blink.Seeder.new()
    |> Blink.put_table("users", [%{id: 1, name: "Alice", email: "alice@example.com"}])
    |> Blink.put_table("posts", [%{id: 1, title: "Welcome", body: "Hi", user_id: 1}])
  end

  defp ids(table) do
    Repo.all(from(r in table, select: r.id, order_by: r.id))
  end

  describe "run/3 with truncate: true" do
    test "re-running replaces the tables' contents" do
      seeder = users_and_posts_seeder()

      assert :ok = Blink.Seeder.run(seeder, Repo, truncate: true)
      assert :ok = Blink.Seeder.run(seeder, Repo, truncate: true)

      assert ids("users") == [1]
      assert ids("posts") == [1]
    end

    test "removes rows the seed does not declare" do
      Repo.query!("INSERT INTO users (id, name) VALUES (99, 'Stray')")

      assert :ok = Blink.Seeder.run(users_and_posts_seeder(), Repo, truncate: true)

      assert ids("users") == [1]
    end

    test "a failed atomic re-seed rolls back to the previous contents" do
      assert :ok = Blink.Seeder.run(users_and_posts_seeder(), Repo)

      failing =
        Blink.Seeder.new()
        |> Blink.put_table("users", [%{id: 2, name: "Bob", email: "bob@example.com"}])
        |> Blink.put_table("posts", [%{id: 2, title: "T", body: "B", user_id: 2}, %{nope: 1}])

      assert_raise Blink.RowError, fn ->
        Blink.Seeder.run(failing, Repo, truncate: true)
      end

      assert ids("users") == [1]
      assert ids("posts") == [1]
    end

    test "a foreign key from an undeclared table fails the truncate" do
      seeder = Blink.put_table(Blink.Seeder.new(), "users", [%{id: 1, name: "Alice"}])

      assert_raise Postgrex.Error, ~r/foreign key/, fn ->
        Blink.Seeder.run(seeder, Repo, truncate: true)
      end
    end

    test "a seeder with no tables truncates nothing" do
      assert :ok = Blink.Seeder.run(Blink.Seeder.new(), Repo, truncate: true)
    end

    test "truncate cannot be set per-table" do
      assert_raise ArgumentError, ~r/cannot be set per-table/, fn ->
        Blink.Seeder.with_table(
          Blink.Seeder.new(),
          "users",
          fn _seeder, _name -> [] end,
          truncate: true
        )
      end
    end

    test "a non-boolean value raises" do
      assert_raise ArgumentError, ~r/invalid value :yes for option :truncate/, fn ->
        Blink.Seeder.run(users_and_posts_seeder(), Repo, truncate: :yes)
      end
    end

    test "an adapter without truncate/3 raises" do
      seeder = Blink.put_table(Blink.Seeder.new(), "users", [%{id: 1}])

      assert_raise ArgumentError, ~r/truncate\/3/, fn ->
        Blink.Seeder.run(seeder, Repo, adapter: NoTruncateAdapter, truncate: true)
      end
    end
  end

  describe "copy_to_table/4 with truncate: true" do
    test "replaces the table's contents" do
      assert :ok = Blink.copy_to_table([%{position: 1}], "serial_items", Repo)

      assert :ok =
               Blink.copy_to_table([%{position: 2}, %{position: 3}], "serial_items", Repo,
                 truncate: true
               )

      positions = Repo.all(from(s in "serial_items", select: s.position, order_by: s.position))
      assert positions == [2, 3]
    end

    test "RESTART IDENTITY makes database-assigned ids deterministic" do
      for _run <- 1..2 do
        assert :ok =
                 Blink.copy_to_table([%{position: 1}, %{position: 2}], "serial_items", Repo,
                   truncate: true
                 )

        assert ids("serial_items") == [1, 2]
      end
    end

    test "an empty input still truncates" do
      assert :ok = Blink.copy_to_table([%{position: 1}], "serial_items", Repo)
      assert :ok = Blink.copy_to_table([], "serial_items", Repo, truncate: true)

      assert Repo.all(from(s in "serial_items", select: count())) == [0]
    end

    test "a failed atomic copy rolls the truncate back" do
      assert :ok = Blink.copy_to_table([%{position: 1}], "serial_items", Repo)

      assert_raise Blink.RowError, fn ->
        Blink.copy_to_table([%{position: 2}, %{nope: 3}], "serial_items", Repo, truncate: true)
      end

      assert Repo.all(from(s in "serial_items", select: s.position)) == [1]
    end
  end
end
