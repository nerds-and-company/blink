defmodule BlinkIntegrationTest do
  use ExUnit.Case, async: true

  import Ecto.Query, warn: false

  alias BlinkIntegrationTest.Dummy
  alias BlinkTest.Repo

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

  describe "special characters in values" do
    test "handles pipe delimiter in strings" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "Alice|Bob", email: "test|pipe@example.com"},
            %{id: 2, name: "a|b|c|d", email: "many|pipes|here@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice|Bob", "test|pipe@example.com"},
               {2, "a|b|c|d", "many|pipes|here@example.com"}
             ]
    end

    test "handles double quotes in strings" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "Alice \"The Great\"", email: "alice@example.com"},
            %{id: 2, name: "Say \"Hello\"", email: "bob@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice \"The Great\"", "alice@example.com"},
               {2, "Say \"Hello\"", "bob@example.com"}
             ]
    end

    test "handles newlines in strings" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "Alice\nNewline", email: "alice@example.com"},
            %{id: 2, name: "Line1\r\nLine2", email: "bob@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice\nNewline", "alice@example.com"},
               {2, "Line1\r\nLine2", "bob@example.com"}
             ]
    end

    test "handles backslashes in strings" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "C:\\Users\\Alice", email: "alice@example.com"},
            %{id: 2, name: "path\\to\\file", email: "bob@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "C:\\Users\\Alice", "alice@example.com"},
               {2, "path\\to\\file", "bob@example.com"}
             ]
    end

    test "handles literal backslash-N (not NULL)" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "\\N is not null", email: "alice@example.com"},
            %{id: 2, name: "test\\Nvalue", email: "bob@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "\\N is not null", "alice@example.com"},
               {2, "test\\Nvalue", "bob@example.com"}
             ]
    end

    test "handles combined special characters" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "Alice|\"Bob\"\nCharlie", email: "test@example.com"},
            %{id: 2, name: "C:\\path|\"quoted\"\r\n\\N", email: "complex@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice|\"Bob\"\nCharlie", "test@example.com"},
               {2, "C:\\path|\"quoted\"\r\n\\N", "complex@example.com"}
             ]
    end

    test "handles using from_csv with special characters" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          fixtures_path = Path.expand("../fixtures", __DIR__)
          path = Path.join(fixtures_path, "users_special_chars.csv")
          Blink.from_csv(path, transform: &Map.take(&1, ~w[id name email]))
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice|Bob", "test@example.com"},
               {2, "Say \"Hello\"", "quoted@example.com"},
               {3, "Line1\nLine2", "newline@example.com"},
               {4, "C:\\Users\\Test", "backslash@example.com"}
             ]
    end

    test "handles empty strings (not NULL)" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "", email: "empty@example.com"},
            %{id: 2, name: "Bob", email: ""}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "", "empty@example.com"},
               {2, "Bob", ""}
             ]
    end

    test "handles NULL values" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: nil, email: "null_name@example.com"},
            %{id: 2, name: "Bob", email: nil}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, nil, "null_name@example.com"},
               {2, "Bob", nil}
             ]
    end

    test "handles unicode and emojis" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "日本語", email: "japanese@example.com"},
            %{id: 2, name: "Ελληνικά", email: "greek@example.com"},
            %{id: 3, name: "🎉🚀💻", email: "emoji@example.com"},
            %{id: 4, name: "Müller", email: "umlaut@example.com"}
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "日本語", "japanese@example.com"},
               {2, "Ελληνικά", "greek@example.com"},
               {3, "🎉🚀💻", "emoji@example.com"},
               {4, "Müller", "umlaut@example.com"}
             ]
    end
  end

  describe "insert/2" do
    test "inserts data into table" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
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

    test "inserts data into tables with foreign key constraints" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> with_table("posts")
          |> run(Repo)
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
          |> with_table("users")
          |> run(Repo)
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
          |> with_table("users")
          |> run(Repo)
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
          |> with_context("users")
          |> with_table("users")
          |> run(Repo)
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

  describe "JSONB columns" do
    test "inserts nested maps as JSONB" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          [
            %{
              id: 1,
              name: "Alice",
              email: "alice@example.com",
              settings: %{"theme" => "dark", "notifications" => true}
            },
            %{
              id: 2,
              name: "Bob",
              email: "bob@example.com",
              settings: %{"theme" => "light", "notifications" => false}
            }
          ]
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.settings}, order_by: u.id))

      assert users == [
               {1, "Alice", %{"theme" => "dark", "notifications" => true}},
               {2, "Bob", %{"theme" => "light", "notifications" => false}}
             ]
    end

    test "inserts nested maps from JSON file as JSONB" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          fixtures_path = Path.expand("../fixtures", __DIR__)
          path = Path.join(fixtures_path, "users_with_settings.json")

          Blink.from_json(path,
            transform: fn row ->
              %{
                id: row["id"],
                name: row["name"],
                email: "#{String.downcase(row["name"])}@example.com",
                settings: row["settings"]
              }
            end
          )
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.settings}, order_by: u.id))

      assert users == [
               {1, "Alice", %{"theme" => "dark", "notifications" => true}},
               {2, "Bob", %{"theme" => "light", "notifications" => false}}
             ]
    end
  end

  describe "insert/3" do
    test "handles maps with inconsistent key order" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
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

  describe "stream support" do
    test "inserts data from a stream" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          Stream.map(1..5, fn i ->
            %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
          end)
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "User 1", "user1@example.com"},
               {2, "User 2", "user2@example.com"},
               {3, "User 3", "user3@example.com"},
               {4, "User 4", "user4@example.com"},
               {5, "User 5", "user5@example.com"}
             ]
    end

    test "inserts data from dependent streams" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> with_table("posts")
          |> run(Repo)
        end

        def table(_store, "users") do
          Stream.map(1..3, fn i ->
            %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
          end)
        end

        def table(store, "posts") do
          Stream.flat_map(store.tables["users"], fn user ->
            for i <- 1..2 do
              %{
                id: (user.id - 1) * 2 + i,
                title: "Post #{i} by #{user.name}",
                body: "Content",
                user_id: user.id
              }
            end
          end)
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name}, order_by: u.id))

      assert users == [
               {1, "User 1"},
               {2, "User 2"},
               {3, "User 3"}
             ]

      posts = Repo.all(from(p in "posts", select: {p.id, p.title, p.user_id}, order_by: p.id))

      assert posts == [
               {1, "Post 1 by User 1", 1},
               {2, "Post 2 by User 1", 1},
               {3, "Post 1 by User 2", 2},
               {4, "Post 2 by User 2", 2},
               {5, "Post 1 by User 3", 3},
               {6, "Post 2 by User 3", 3}
             ]
    end

    test "handles empty stream" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo)
        end

        def table(_store, "users") do
          Stream.map([], fn x -> x end)
        end
      end

      assert {:ok, _} = Dummy.call()

      users = Repo.all(from(u in "users", select: count()))
      assert users == [0]
    end
  end
end
