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

      assert %Store{seeds: %{}, helpers: %{}} = Dummy.new_store()
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

        def build(_, _), do: []
      end

      assert %{seeds: %{:atom => _}} = Dummy.run()
      assert %{seeds: %{"string" => _}} = Dummy.run()
    end

    test "raises if table name already exists in seeds" do
      defmodule Dummy do
        use Blink

        def run do
          new_store()
          |> put_table("table_name")
          |> put_table("table_name")
        end

        def build(_, _), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.run()
      end
    end
  end

  describe "put_helper/2" do
    test "accepts atom and string keys" do
      defmodule Dummy do
        use Blink

        def run do
          new_store()
          |> put_helper(:atom)
          |> put_helper("string")
        end

        def build(_, _, :helpers), do: []
      end

      assert %{helpers: %{:atom => _}} = Dummy.run()
      assert %{helpers: %{"string" => _}} = Dummy.run()
    end

    test "raises if key already exists in helpers" do
      defmodule Dummy do
        use Blink

        def run do
          new_store()
          |> put_helper("key")
          |> put_helper("key")
        end

        def build(_, _, :helpers), do: []
      end

      assert_raise ArgumentError, fn ->
        Dummy.run()
      end
    end
  end
end
