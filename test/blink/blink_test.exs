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

  describe "new_store/0" do
    test "returns an empty Store" do
      defmodule Dummy do
        use Blink
      end

      assert %Store{tables: %{}, context: %{}} = Dummy.new_store()
    end
  end

  describe "put_table/2" do
    test "accepts atom and string table names" do
      defmodule Dummy do
        use Blink

        def run do
          new_store()
          |> put_table(:atom)
          |> put_table("string")
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
          new_store()
          |> put_table("table_name")
          |> put_table("table_name")
        end

        def table(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.run()
      end
    end
  end

  describe "put_context/2" do
    test "accepts atom and string keys" do
      defmodule Dummy do
        use Blink

        def run do
          new_store()
          |> put_context(:atom)
          |> put_context("string")
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
          new_store()
          |> put_context("key")
          |> put_context("key")
        end

        def context(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.run()
      end
    end
  end
end
