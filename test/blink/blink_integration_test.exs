defmodule BlinkIntegrationTest do
  use ExUnit.Case, async: true

  alias BlinkIntegrationTest.Dummy
  alias BlinkTest.Repo

  import Ecto.Query, warn: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    on_exit(fn ->
      :code.delete(Dummy)
      :code.purge(Dummy)
      Ecto.Adapters.SQL.Sandbox.checkin(Repo)
    end)

    :ok
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

      assert :ok = Dummy.call()

      # Verify data was inserted
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice", "alice@example.com"},
               {2, "Bob", "bob@example.com"}
             ]
    end

    test "inserts data into multiple tables" do
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

      assert :ok = Dummy.call()

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

      assert :ok = Dummy.call()

      # Verify no data was inserted
      users = Repo.all(from(u in "users", select: count()))
      assert users == [0]
    end

    test "uses context to build table data" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_context("user_ids")
          |> add_table("posts")
          |> insert(Repo)
        end

        def context(_store, "user_ids") do
          [1, 2, 3]
        end

        def table(store, "posts") do
          user_ids = store.context["user_ids"]

          Enum.map(user_ids, fn id ->
            %{id: id, title: "Post #{id}", body: "Body #{id}", user_id: id}
          end)
        end
      end

      assert :ok = Dummy.call()

      # Verify posts were created using context
      posts = Repo.all(from(p in "posts", select: {p.id, p.title}, order_by: p.id))
      assert posts == [{1, "Post 1"}, {2, "Post 2"}, {3, "Post 3"}]
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
      assert {:error, _reason} = Dummy.call()

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

      assert :ok = Dummy.call()

      # Verify only users table has data
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}))
      assert [{2, "Bob", "bob@example.com"}] == users
    end
  end

  describe "insert/3" do
    test "inserts data with options" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo, batch_size: 1)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{id: 2, name: "Bob", email: "bob@example.com"},
            %{id: 3, name: "Charlie", email: "charlie@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

      # Verify data was inserted with batch_size option
      users = Repo.all(from(u in "users", select: {u.id, u.name}, order_by: u.id))

      assert users == [
               {1, "Alice"},
               {2, "Bob"},
               {3, "Charlie"}
             ]
    end

    test "inserts large dataset with custom batch size" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(Repo, batch_size: 5)
        end

        def table(_store, "users") do
          for i <- 1..10 do
            %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
          end
        end
      end

      assert :ok = Dummy.call()

      # Verify all data was inserted
      user_count = Repo.one(from(u in "users", select: count()))
      assert user_count == 10

      # Verify some sample data
      first_user = Repo.one(from(u in "users", where: u.id == 1, select: u.name))
      assert first_user == "User 1"

      last_user = Repo.one(from(u in "users", where: u.id == 10, select: u.name))
      assert last_user == "User 10"
    end
  end
end
