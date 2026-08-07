defmodule BlinkTest do
  use ExUnit.Case, async: false

  alias BlinkTest.Dummy

  setup do
    on_exit(fn ->
      :code.delete(Dummy)
      :code.purge(Dummy)
    end)
  end

  describe "with_table/2" do
    test "accepts atom and string table names" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table(:atom)
          |> with_table("string")
        end

        def table(_, _), do: []
      end

      assert %{tables: %{:atom => _}} = Dummy.call()
      assert %{tables: %{"string" => _}} = Dummy.call()
    end

    test "raises if table name already exists" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("table_name")
          |> with_table("table_name")
        end

        def table(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.call()
      end
    end
  end

  describe "with_table/2 with a list of names" do
    test "declares each table in order" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table(["users", "posts"])
        end

        def table(_seeder, "users"), do: [%{id: 1}]

        def table(seeder, "posts") do
          # Reads a table declared earlier in the same list, proving the names
          # are declared sequentially rather than all at once.
          Enum.map(seeder.tables["users"], &%{id: &1.id + 1})
        end
      end

      seeder = Dummy.call()

      assert seeder.table_order == ["users", "posts"]
      assert seeder.tables["posts"] == [%{id: 2}]
    end

    test "applies opts to every table in the list" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table(["users", "posts"], batch_size: 100)
        end

        def table(_seeder, _name), do: []
      end

      assert %{table_opts: %{"users" => [batch_size: 100], "posts" => [batch_size: 100]}} =
               Dummy.call()
    end

    test "raises if a listed name is already declared" do
      defmodule Dummy do
        use Blink

        def call do
          new() |> with_table(["users", "users"])
        end

        def table(_seeder, _name), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.call()
      end
    end

    test "raises MissingClauseError for a listed name with no clause" do
      defmodule Dummy do
        use Blink

        def call do
          new() |> with_table(["users", "missing"])
        end

        def table(_seeder, "users"), do: []
      end

      assert_raise Blink.MissingClauseError, fn ->
        Dummy.call()
      end
    end
  end

  describe "with_context/2" do
    test "accepts atom and string keys" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_context(:atom)
          |> with_context("string")
        end

        def context(_, _), do: []
      end

      assert %{context: %{:atom => _}} = Dummy.call()
      assert %{context: %{"string" => _}} = Dummy.call()
    end

    test "raises if key already exists in context" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_context("key")
          |> with_context("key")
        end

        def context(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.call()
      end
    end
  end

  describe "run/2" do
    test "can be overridden with custom implementation" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(BlinkTest.Repo)
        end

        def table(_seeder, "users") do
          [%{id: 1, name: "Alice"}]
        end

        def run(seeder, repo) do
          assert %Blink.Seeder{} = seeder
          assert BlinkTest.Repo = repo

          :some_custom_result
        end
      end

      assert :some_custom_result = Dummy.call()
    end
  end

  describe "run/3" do
    test "can be overridden with custom implementation" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(BlinkTest.Repo, timeout: 60_000)
        end

        def table(_seeder, "users") do
          [%{id: 1, name: "Alice"}]
        end

        def run(seeder, repo, opts) do
          assert %Blink.Seeder{} = seeder
          assert BlinkTest.Repo = repo
          assert [timeout: 60_000] = opts

          :some_custom_result
        end
      end

      assert :some_custom_result = Dummy.call()
    end
  end

  describe "table/2 callback" do
    test "raises MissingClauseError when no table/2 clause is defined at all" do
      defmodule NoTableClauses do
        use Blink

        def call do
          new()
          |> with_table("users")
        end
      end

      assert_raise Blink.MissingClauseError,
                   ~r/declares "users" with with_table\/2, but no table\/2 clause matches "users"/,
                   fn -> NoTableClauses.call() end
    end

    test "raises MissingClauseError when a declared table has no matching clause" do
      defmodule SomeTableClauses do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> with_table("posts")
        end

        def table(_seeder, "users"), do: [%{id: 1}]
      end

      error = assert_raise Blink.MissingClauseError, fn -> SomeTableClauses.call() end

      message = Exception.message(error)
      assert message =~ ~s(declares "posts" with with_table/2)
      assert message =~ ~s{def table(_seeder, "posts") do}
    end

    test "names atom table names as atoms" do
      defmodule AtomTableName do
        use Blink

        def call, do: new() |> with_table(:events)
      end

      assert_raise Blink.MissingClauseError,
                   ~r/no table\/2 clause matches :events/,
                   fn -> AtomTableName.call() end
    end

    test "does not translate a FunctionClauseError raised inside a clause body" do
      defmodule RaisesInBody do
        use Blink

        def call, do: new() |> with_table("users")

        def table(_seeder, "users"), do: pick(:unmatched)

        defp pick(:matched), do: []
      end

      assert_raise FunctionClauseError, fn -> RaisesInBody.call() end
    end
  end

  describe "context/2 callback" do
    test "raises MissingClauseError when no context/2 clause is defined at all" do
      defmodule NoContextClauses do
        use Blink

        def call do
          new()
          |> with_context("data")
        end
      end

      assert_raise Blink.MissingClauseError,
                   ~r/declares "data" with with_context\/2, but no context\/2 clause matches "data"/,
                   fn -> NoContextClauses.call() end
    end

    test "raises MissingClauseError when a declared key has no matching clause" do
      defmodule SomeContextClauses do
        use Blink

        def call do
          new()
          |> with_context("timestamps")
          |> with_context("missing")
        end

        def context(_seeder, "timestamps"), do: [1, 2]
      end

      error = assert_raise Blink.MissingClauseError, fn -> SomeContextClauses.call() end

      message = Exception.message(error)
      assert message =~ ~s(declares "missing" with with_context/2)
      assert message =~ ~s{def context(_seeder, "missing") do}
    end
  end
end
