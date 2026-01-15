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

        def table(_store, "users") do
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
          |> run(BlinkTest.Repo, batch_size: 500)
        end

        def table(_store, "users") do
          [%{id: 1, name: "Alice"}]
        end

        def run(seeder, repo, opts) do
          assert %Blink.Seeder{} = seeder
          assert BlinkTest.Repo = repo
          assert [batch_size: 500] = opts

          :some_custom_result
        end
      end

      assert :some_custom_result = Dummy.call()
    end
  end

  describe "table/2 callback" do
    test "raises ArgumentError when table/2 clause is missing" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_table("users")
        end
      end

      assert_raise ArgumentError,
                   "you must define table/2 clauses that correspond with your calls to with_table/2",
                   fn ->
                     Dummy.call()
                   end
    end
  end

  describe "context/2 callback" do
    test "raises ArgumentError when context/2 clause is missing" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> with_context("data")
        end
      end

      assert_raise ArgumentError,
                   "you must define context/2 clauses that correspond with your calls to with_context/2",
                   fn ->
                     Dummy.call()
                   end
    end
  end
end
