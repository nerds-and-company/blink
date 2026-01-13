defmodule BlinkIntegrationTest do
  use ExUnit.Case, async: true

  alias BlinkIntegrationTest.Dummy
  alias BlinkTest.Repo

  import Ecto.Query, warn: false

  @moduletag capture_log: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    on_exit(fn ->
      :code.delete(Dummy)
      :code.purge(Dummy)
      Ecto.Adapters.SQL.Sandbox.checkin(Repo)
    end)

    :ok
  end

  describe "from file insert/2" do
    test "inserts data into table from csv" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo)
        end

        def table(_store, "users") do
          fixtures_path = Path.expand("../fixtures", __DIR__)
          path = Path.join(fixtures_path, "users.csv")
          Blink.from_csv(path, transform: &Map.take(&1, ~w[id name email]))
        end
      end

      assert {:ok, _} = Dummy.call()

      # Verify data was inserted
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice", "alice@example.com"},
               {2, "Bob", "bob@example.com"},
               {3, "Charlie", "charlie@example.com"}
             ]
    end

    test "inserts data into table from csv stream" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo)
        end

        def table(_store, "users") do
          fixtures_path = Path.expand("../fixtures", __DIR__)
          path = Path.join(fixtures_path, "users.csv")
          Blink.stream_from_csv(path, transform: &Map.take(&1, ~w[id name email]))
        end
      end

      assert {:ok, _} = Dummy.call()

      # Verify data was inserted
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice", "alice@example.com"},
               {2, "Bob", "bob@example.com"},
               {3, "Charlie", "charlie@example.com"}
             ]
    end
  end

  describe "insert/2" do
    test "inserts data into table" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{id: 2, name: "Bob", email: "bob@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      # Verify data was inserted
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice", "alice@example.com"},
               {2, "Bob", "bob@example.com"}
             ]
    end

    test "inserts strings with | pipes" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "A|l|i|c|e", email: "alice@example.com"},
            %{id: 2, name: "B|o|b", email: "bob@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      # Verify data was inserted
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "A|l|i|c|e", "alice@example.com"},
               {2, "B|o|b", "bob@example.com"}
             ]
    end

    test "inserts strings with \" quotes" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "Ali\"ce", email: "alice@example.com"},
            %{id: 2, name: "B\"o\"b", email: "bob@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      # Verify data was inserted
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Ali\"ce", "alice@example.com"},
               {2, "B\"o\"b", "bob@example.com"}
             ]
    end

    test "inserts data into tables with foreign key constraints" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> add_table("posts")
          |> insert(Repo)
        end

        def table(_store, "users") do
          [%{id: 1, name: "Alice", email: "alice@example.com"}]
        end

        def table(_store, "posts") do
          [
            %{id: 1, title: "First Post", body: "Hello world", user_id: 1},
            %{id: 2, title: "Second Post", body: "Another post", user_id: 1}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      # Verify users
      users = Repo.all(from(u in "users", select: u.name))
      assert users == ["Alice"]

      # Verify posts
      posts = Repo.all(from(p in "posts", select: {p.id, p.title}, order_by: p.id))

      assert posts == [
               {1, "First Post"},
               {2, "Second Post"}
             ]
    end

    test "handles empty tables" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo)
        end

        def table(_store, "users"), do: []
      end

      assert {:ok, _} = Dummy.call()

      # Verify no data was inserted
      users = Repo.all(from(u in "users", select: count()))
      assert users == [0]
    end

    test "rolls back transaction on error" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo)
        end

        def table(_store, "users") do
          # This will fail because id is required to be unique
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{id: 1, name: "Bob", email: "bob@example.com"}
          ]
        end
      end

      # Should return error
      assert_raise Postgrex.Error, fn ->
        Dummy.call()
      end

      # Verify nothing was inserted (transaction rolled back)
      users = Repo.all(from(u in "users", select: count()))
      assert users == [0]
    end

    test "does not insert context data" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_context("users")
          |> add_table("users")
          |> insert(Repo)
        end

        def context(_store, "users") do
          [%{id: 1, name: "Alice", email: "alice@example.com"}]
        end

        def table(_store, "users") do
          [%{id: 2, name: "Bob", email: "bob@example.com"}]
        end
      end

      assert {:ok, _} = Dummy.call()

      # Verify only users table has data
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}))
      assert [{2, "Bob", "bob@example.com"}] == users
    end
  end

  describe "insert/3" do
    test "inserts with custom batch size" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo, batch_size: 2)
        end

        def table(_store, "users") do
          for i <- 1..5 do
            %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
          end
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert length(users) == 5

      assert users == [
               {1, "User 1", "user1@example.com"},
               {2, "User 2", "user2@example.com"},
               {3, "User 3", "user3@example.com"},
               {4, "User 4", "user4@example.com"},
               {5, "User 5", "user5@example.com"}
             ]
    end

    test "inserts with batching disabled" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo, batch_size: :infinity)
        end

        def table(_store, "users") do
          for i <- 1..5 do
            %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
          end
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert length(users) == 5

      assert users == [
               {1, "User 1", "user1@example.com"},
               {2, "User 2", "user2@example.com"},
               {3, "User 3", "user3@example.com"},
               {4, "User 4", "user4@example.com"},
               {5, "User 5", "user5@example.com"}
             ]
    end

    test "handles maps with inconsistent key order" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo)
        end

        def table(_store, "users") do
          # Maps with keys in different orders (Map.keys/1 order is not guaranteed)
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{email: "bob@example.com", name: "Bob", id: 2},
            %{name: "Charlie", id: 3, email: "charlie@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      # Verify all data was inserted correctly regardless of key order
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice", "alice@example.com"},
               {2, "Bob", "bob@example.com"},
               {3, "Charlie", "charlie@example.com"}
             ]
    end
  end
end
