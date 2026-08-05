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
    end)

    :ok
  end

  describe "run/2" do
    test "inserts data into table" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
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

    test "inserts data into tables with foreign key constraints" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> with_table("posts")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [%{id: 1, name: "Alice", email: "alice@example.com"}]
        end

        def table(_seeder, "posts") do
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
          |> with_table("users")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users"), do: []
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          # This will fail because id is required to be unique
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{id: 1, name: "Bob", email: "bob@example.com"}
          ]
        end
      end

      # Should raise an exception
      assert_raise Postgrex.Error, fn -> Dummy.call() end

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
          |> run(Repo, concurrency: 1)
        end

        def context(_seeder, "users") do
          [%{id: 1, name: "Alice", email: "alice@example.com"}]
        end

        def table(_seeder, "users") do
          [%{id: 2, name: "Bob", email: "bob@example.com"}]
        end
      end

      assert :ok = Dummy.call()

      # Verify only users table has data
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}))
      assert [{2, "Bob", "bob@example.com"}] == users
    end

    test "handles maps with inconsistent key order" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          # Maps with keys in different orders (Map.keys/1 order is not guaranteed)
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{email: "bob@example.com", name: "Bob", id: 2},
            %{name: "Charlie", id: 3, email: "charlie@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

      # Verify all data was inserted correctly regardless of key order
      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice", "alice@example.com"},
               {2, "Bob", "bob@example.com"},
               {3, "Charlie", "charlie@example.com"}
             ]
    end
  end

  describe "atomicity" do
    # The all-or-nothing counterpart (atomic: true) is covered in
    # Blink.AtomicTest.
    test "with atomic: false, earlier tables stay committed when a later table fails" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> with_table("posts")
          |> run(Repo, atomic: false, concurrency: 1)
        end

        def table(_seeder, "users") do
          [%{id: 1, name: "Alice", email: "alice@example.com"}]
        end

        def table(_seeder, "posts") do
          # user_id 999 has no matching user, so the posts COPY fails after the
          # users COPY has already committed.
          [%{id: 1, title: "Post", body: "Body", user_id: 999}]
        end
      end

      assert_raise Postgrex.Error, fn -> Dummy.call() end

      assert Repo.all(from(u in "users", select: count())) == [1]
      assert Repo.all(from(p in "posts", select: count())) == [0]
    end
  end

  describe "stream support" do
    test "inserts data from a stream" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          Stream.map(1..5, fn i ->
            %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
          end)
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          Stream.map(1..3, fn i ->
            %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
          end)
        end

        def table(seeder, "posts") do
          Stream.flat_map(seeder.tables["users"], fn user ->
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

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          Stream.map([], fn x -> x end)
        end
      end

      assert :ok = Dummy.call()

      users = Repo.all(from(u in "users", select: count()))
      assert users == [0]
    end
  end

  describe "JSONB columns" do
    test "inserts nested maps as JSONB" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
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

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
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

      assert :ok = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.settings}, order_by: u.id))

      assert users == [
               {1, "Alice", %{"theme" => "dark", "notifications" => true}},
               {2, "Bob", %{"theme" => "light", "notifications" => false}}
             ]
    end

    test "inserts nested maps from CSV file as JSONB" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          fixtures_path = Path.expand("../fixtures", __DIR__)
          path = Path.join(fixtures_path, "users_with_settings.csv")

          Blink.from_csv(path,
            transform: fn row ->
              %{
                id: String.to_integer(row["id"]),
                name: row["name"],
                email: row["email"],
                settings: Jason.decode!(row["settings"])
              }
            end
          )
        end
      end

      assert :ok = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.settings}, order_by: u.id))

      assert users == [
               {1, "Alice",
                %{"theme" => "dark", "notifications" => %{"email" => true, "sms" => false}}},
               {2, "Bob",
                %{"theme" => "light", "notifications" => %{"email" => false, "sms" => true}}}
             ]
    end

    test "correctly encodes many rows that share JSONB maps across batches" do
      settings_a = %{"theme" => "dark", "flags" => %{"beta" => true}}
      settings_b = %{"theme" => "light", "flags" => %{"beta" => false}}

      rows =
        Enum.map(1..300, fn i ->
          settings = if rem(i, 2) == 0, do: settings_a, else: settings_b
          %{id: i, name: "User #{i}", email: "u#{i}@example.com", settings: settings}
        end)

      # batch_size 50 forces multiple batches; interleaved maps catch a cache
      # that returns the wrong memoized value.
      assert :ok = Blink.copy_to_table(rows, "users", Repo, concurrency: 1, batch_size: 50)

      stored = Repo.all(from(u in "users", select: {u.id, u.settings}, order_by: u.id))

      assert length(stored) == 300

      assert Enum.all?(stored, fn {id, settings} ->
               settings == if(rem(id, 2) == 0, do: settings_a, else: settings_b)
             end)
    end
  end

  describe "array columns" do
    test "encodes Elixir lists as PostgreSQL array literals" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("array_records")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "array_records") do
          [
            %{
              id: 1,
              ints: [1, 2, 3],
              strings: ["a", "b,c", ~s(quote"x), "back\\slash"],
              docs: [%{"k" => 1}, %{"k" => 2, "nested" => %{"x" => true}}],
              matrix: [[1, 2], [3, 4]]
            },
            %{id: 2, ints: [], strings: [], docs: [], matrix: []},
            %{id: 3, ints: [10, nil, 30], strings: nil, docs: nil, matrix: nil}
          ]
        end
      end

      assert :ok = Dummy.call()

      records =
        Repo.all(
          from(r in "array_records",
            select: {r.id, r.ints, r.strings, r.docs, r.matrix},
            order_by: r.id
          )
        )

      assert records == [
               {1, [1, 2, 3], ["a", "b,c", ~s(quote"x), "back\\slash"],
                [%{"k" => 1}, %{"k" => 2, "nested" => %{"x" => true}}], [[1, 2], [3, 4]]},
               {2, [], [], [], []},
               {3, [10, nil, 30], nil, nil, nil}
             ]
    end

    test "escapes special characters and edge values in text[] elements" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("array_records")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "array_records") do
          [
            %{
              id: 10,
              strings: [
                "a|b",
                "line1\nline2",
                "",
                "NULL",
                nil,
                ~s(has"quote),
                "brace{}s",
                "back\\slash"
              ]
            }
          ]
        end
      end

      assert :ok = Dummy.call()

      [strings] = Repo.all(from(r in "array_records", where: r.id == 10, select: r.strings))

      assert strings == [
               "a|b",
               "line1\nline2",
               "",
               "NULL",
               nil,
               ~s(has"quote),
               "brace{}s",
               "back\\slash"
             ]
    end
  end

  describe "special characters in values" do
    test "handles pipe delimiter in strings" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "Alice|Bob", email: "test|pipe@example.com"},
            %{id: 2, name: "a|b|c|d", email: "many|pipes|here@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "Alice \"The Great\"", email: "alice@example.com"},
            %{id: 2, name: "Say \"Hello\"", email: "bob@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "Alice\nNewline", email: "alice@example.com"},
            %{id: 2, name: "Line1\r\nLine2", email: "bob@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "C:\\Users\\Alice", email: "alice@example.com"},
            %{id: 2, name: "path\\to\\file", email: "bob@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "\\N is not null", email: "alice@example.com"},
            %{id: 2, name: "test\\Nvalue", email: "bob@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "Alice|\"Bob\"\nCharlie", email: "test@example.com"},
            %{id: 2, name: "C:\\path|\"quoted\"\r\n\\N", email: "complex@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          fixtures_path = Path.expand("../fixtures", __DIR__)
          path = Path.join(fixtures_path, "users_special_chars.csv")
          Blink.from_csv(path, transform: &Map.take(&1, ~w[id name email]))
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "", email: "empty@example.com"},
            %{id: 2, name: "Bob", email: ""}
          ]
        end
      end

      assert :ok = Dummy.call()

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
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: nil, email: "name@example.com"},
            %{id: 2, name: "Bob", email: nil}
          ]
        end
      end

      assert :ok = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, nil, "name@example.com"},
               {2, "Bob", nil}
             ]
    end

    test "handles unicode and emojis" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo, concurrency: 1)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "日本語", email: "japanese@example.com"},
            %{id: 2, name: "Ελληνικά", email: "greek@example.com"},
            %{id: 3, name: "🎉🚀💻", email: "emoji@example.com"},
            %{id: 4, name: "Müller", email: "umlaut@example.com"}
          ]
        end
      end

      assert :ok = Dummy.call()

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "日本語", "japanese@example.com"},
               {2, "Ελληνικά", "greek@example.com"},
               {3, "🎉🚀💻", "emoji@example.com"},
               {4, "Müller", "umlaut@example.com"}
             ]
    end
  end

  describe "per-table options" do
    test "per-table options override global options" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:blink, :copy, :start]])

      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users", batch_size: 500, concurrency: 1)
          |> run(Repo, batch_size: 10_000, concurrency: 8)
        end

        def table(_seeder, "users"), do: [%{id: 1, name: "Alice", email: "alice@example.com"}]
      end

      Dummy.call()

      assert_received {[:blink, :copy, :start], ^ref, %{}, %{batch_size: 500, concurrency: 1}}
    end

    test "global options are used when no per-table options specified" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:blink, :copy, :start]])

      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(Repo, batch_size: 5_000, concurrency: 1)
        end

        def table(_seeder, "users"), do: [%{id: 1, name: "Alice", email: "alice@example.com"}]
      end

      Dummy.call()

      assert_received {[:blink, :copy, :start], ^ref, %{}, %{batch_size: 5_000, concurrency: 1}}
    end
  end

  describe "batched COPY operations" do
    test "inserts data in batches" do
      items =
        Stream.map(1..100, fn i ->
          %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
        end)

      assert :ok =
               Blink.copy_to_table(items, "users", Repo, batch_size: 10, concurrency: 1)

      users = Repo.all(from(u in "users", select: count()))
      assert users == [100]
    end

    test "handles list input" do
      items =
        Enum.map(1..50, fn i ->
          %{id: i, name: "User #{i}", email: "user#{i}@example.com"}
        end)

      assert :ok =
               Blink.copy_to_table(items, "users", Repo, concurrency: 1)

      users = Repo.all(from(u in "users", select: count()))
      assert users == [50]
    end

    test "handles fewer items than batch size" do
      items = [
        %{id: 1, name: "Alice", email: "alice@example.com"},
        %{id: 2, name: "Bob", email: "bob@example.com"}
      ]

      assert :ok =
               Blink.copy_to_table(items, "users", Repo, concurrency: 1)

      users = Repo.all(from(u in "users", select: {u.id, u.name}, order_by: u.id))

      assert users == [
               {1, "Alice"},
               {2, "Bob"}
             ]
    end

    test "handles empty stream" do
      items = Stream.map([], fn x -> x end)

      assert :ok =
               Blink.copy_to_table(items, "users", Repo, concurrency: 1)

      users = Repo.all(from(u in "users", select: count()))
      assert users == [0]
    end

    test "handles special characters" do
      items = [
        %{id: 1, name: "Alice|Bob", email: "pipe@example.com"},
        %{id: 2, name: "Say \"Hello\"", email: "quote@example.com"},
        %{id: 3, name: "Line1\nLine2", email: "newline@example.com"}
      ]

      assert :ok =
               Blink.copy_to_table(items, "users", Repo, concurrency: 1)

      users = Repo.all(from(u in "users", select: {u.id, u.name, u.email}, order_by: u.id))

      assert users == [
               {1, "Alice|Bob", "pipe@example.com"},
               {2, "Say \"Hello\"", "quote@example.com"},
               {3, "Line1\nLine2", "newline@example.com"}
             ]
    end
  end
end
