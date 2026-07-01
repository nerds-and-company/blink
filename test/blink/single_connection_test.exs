defmodule Blink.SingleConnectionTest do
  use ExUnit.Case, async: true

  import Ecto.Query, warn: false

  alias BlinkTest.Repo

  @moduletag capture_log: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  describe "strategy: :single_connection" do
    test "inserts rows" do
      rows = [
        %{id: 1, name: "Alice", email: "alice@example.com"},
        %{id: 2, name: "Bob", email: "bob@example.com"}
      ]

      assert :ok = Blink.copy_to_table(rows, "users", Repo, strategy: :single_connection)

      users = Repo.all(from(u in "users", select: {u.id, u.name}, order_by: u.id))
      assert users == [{1, "Alice"}, {2, "Bob"}]
    end

    test "encodes JSONB maps correctly" do
      rows = [%{id: 1, name: "Alice", email: "alice@example.com", settings: %{"theme" => "dark"}}]

      assert :ok = Blink.copy_to_table(rows, "users", Repo, strategy: :single_connection)

      assert Repo.all(from(u in "users", select: u.settings)) == [%{"theme" => "dark"}]
    end

    test "copies from a stream" do
      stream =
        Stream.map(1..100, fn i -> %{id: i, name: "User #{i}", email: "u#{i}@example.com"} end)

      assert :ok =
               Blink.copy_to_table(stream, "users", Repo,
                 strategy: :single_connection,
                 batch_size: 10
               )

      assert Repo.all(from(u in "users", select: count())) == [100]
    end

    test "handles empty input" do
      assert :ok = Blink.copy_to_table([], "users", Repo, strategy: :single_connection)
      assert Repo.all(from(u in "users", select: count())) == [0]
    end

    test "preserves input row order across parallel-encoded batches (ordered: true default)" do
      rows = Enum.map(1..500, fn i -> %{position: i} end)

      assert :ok =
               Blink.copy_to_table(rows, "serial_items", Repo,
                 strategy: :single_connection,
                 batch_size: 25,
                 encoder_concurrency: 8
               )

      # Serial ids are assigned in COPY insertion order, so reading by id must
      # return the positions in their original input order.
      positions = Repo.all(from(s in "serial_items", select: s.position, order_by: s.id))
      assert positions == Enum.to_list(1..500)
    end

    test "ordered: false still copies every row" do
      rows = Enum.map(1..500, fn i -> %{position: i} end)

      assert :ok =
               Blink.copy_to_table(rows, "serial_items", Repo,
                 strategy: :single_connection,
                 batch_size: 25,
                 encoder_concurrency: 8,
                 ordered: false
               )

      positions = Repo.all(from(s in "serial_items", select: s.position)) |> Enum.sort()
      assert positions == Enum.to_list(1..500)
    end

    test "rolls back the whole COPY on a bad row" do
      rows = [
        %{id: 1, name: "Alice", email: "alice@example.com"},
        %{id: 1, name: "Bob", email: "bob@example.com"}
      ]

      assert_raise Postgrex.Error, fn ->
        Blink.copy_to_table(rows, "users", Repo, strategy: :single_connection)
      end

      assert Repo.all(from(u in "users", select: count())) == [0]
    end

    test "surfaces encoder errors as a descriptive error and rolls back" do
      rows = [%{id: 1, name: {:not, :encodable}, email: "alice@example.com"}]

      assert_raise RuntimeError, ~r/COPY encode failed/, fn ->
        Blink.copy_to_table(rows, "users", Repo, strategy: :single_connection)
      end

      assert Repo.all(from(u in "users", select: count())) == [0]
    end

    test "raises for an invalid strategy" do
      assert_raise ArgumentError, ~r/invalid :strategy/, fn ->
        Blink.copy_to_table([%{id: 1, name: "A", email: "a@example.com"}], "users", Repo,
          strategy: :bogus
        )
      end
    end
  end

  describe "run/3 with strategy: :single_connection" do
    test "rolls back all tables when a later table fails" do
      defmodule SingleConnSeeder do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> with_table("posts")
          |> run(Repo, strategy: :single_connection)
        end

        def table(_seeder, "users") do
          [%{id: 1, name: "Alice", email: "alice@example.com"}]
        end

        def table(_seeder, "posts") do
          # user_id 999 has no matching user, so the posts COPY fails after the
          # users COPY has already run within the same surrounding transaction.
          [%{id: 1, title: "Post", body: "Body", user_id: 999}]
        end
      end

      on_exit(fn ->
        :code.delete(SingleConnSeeder)
        :code.purge(SingleConnSeeder)
      end)

      assert_raise Postgrex.Error, fn -> SingleConnSeeder.call() end

      assert Repo.all(from(u in "users", select: count())) == [0]
      assert Repo.all(from(p in "posts", select: count())) == [0]
    end
  end
end
