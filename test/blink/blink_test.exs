defmodule BlinkTest do
  use ExUnit.Case, async: false

  alias BlinkTest.Dummy

  @moduletag capture_log: true

  setup do
    on_exit(fn ->
      :code.delete(Dummy)
      :code.purge(Dummy)
    end)
  end

  describe "add_table/2" do
    test "accepts atom and string table names" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table(:atom)
          |> add_table("string")
        end

        def table(_, _), do: []
      end

      assert %{tables: %{"atom" => _}} = Dummy.call()
      assert %{tables: %{"string" => _}} = Dummy.call()
    end

    test "raises if table name already exists" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("table_name")
          |> add_table("table_name")
        end

        def table(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.call()
      end
    end
  end

  describe "add_context/2" do
    test "accepts atom and string keys" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_context(:atom)
          |> add_context("string")
        end

        def context(_, _), do: []
      end

      assert %{context: %{"atom" => _}} = Dummy.call()
      assert %{context: %{"string" => _}} = Dummy.call()
    end

    test "raises if key already exists in context" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_context("key")
          |> add_context("key")
        end

        def context(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.call()
      end
    end
  end

  describe "insert/2" do
    test "can be overridden with custom implementation" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(BlinkTest.Repo)
        end

        def table(_store, "users") do
          [%{id: 1, name: "Alice"}]
        end

        def insert(store, repo) do
          assert %Blink.Store{} = store
          assert BlinkTest.Repo = repo

          :some_custom_result
        end
      end

      assert :some_custom_result = Dummy.call()
    end
  end

  describe "insert/3" do
    test "can be overridden with custom implementation" do
      defmodule Dummy do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> insert(BlinkTest.Repo, batch_size: 500)
        end

        def table(_store, "users") do
          [%{id: 1, name: "Alice"}]
        end

        def insert(store, repo, opts) do
          assert %Blink.Store{} = store
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
          |> add_table("users")
        end
      end

      assert_raise ArgumentError,
                   "you must define table/2 clauses that correspond with your calls to add_table/2",
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
          |> add_context("data")
        end
      end

      assert_raise ArgumentError,
                   "you must define context/2 clauses that correspond with your calls to add_context/2",
                   fn ->
                     Dummy.call()
                   end
    end
  end
end
