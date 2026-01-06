defmodule BlinkTest do
  use ExUnit.Case, async: false

  alias Blink.Store
  alias BlinkTest.Dummy

  setup do
    on_exit(fn ->
      :code.purge(Dummy)
      :code.delete(Dummy)
    end)
  end

  describe "new/0" do
    test "returns an empty Store" do
      defmodule Dummy do
        use Blink
      end

      assert %Store{tables: %{}, context: %{}} = Dummy.new()
    end
  end

  describe "add_table/2" do
    test "accepts atom and string table names" do
      defmodule Dummy do
        use Blink

        def run do
          new()
          |> add_table(:atom)
          |> add_table("string")
        end

        def table(_, _), do: []
      end

      assert %{tables: %{:atom => _}} = Dummy.run()
      assert %{tables: %{"string" => _}} = Dummy.run()
    end

    test "raises if table name already exists under :tables" do
      defmodule Dummy do
        use Blink

        def run do
          new()
          |> add_table("table_name")
          |> add_table("table_name")
        end

        def table(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.run()
      end
    end
  end

  describe "add_context/2" do
    test "accepts atom and string keys" do
      defmodule Dummy do
        use Blink

        def run do
          new()
          |> add_context(:atom)
          |> add_context("string")
        end

        def context(_, _), do: []
      end

      assert %{context: %{:atom => _}} = Dummy.run()
      assert %{context: %{"string" => _}} = Dummy.run()
    end

    test "raises if key already exists in context" do
      defmodule Dummy do
        use Blink

        def run do
          new()
          |> add_context("key")
          |> add_context("key")
        end

        def context(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.run()
      end
    end
  end
end
