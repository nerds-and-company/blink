defmodule Blink.AdapterTest do
  use ExUnit.Case, async: true

  describe "copy_to_table/4" do
    test "raises UndefinedFunctionError when adapter module doesn't implement call/4" do
      # Define a module that doesn't implement the Blink.Adapter behaviour
      defmodule InvalidAdapter do
        # Intentionally not implementing call/4
      end

      assert_raise UndefinedFunctionError, fn ->
        Blink.copy_to_table([], "users", TestRepo, adapter: Blink.AdapterTest.InvalidAdapter)
      end
    end

    test "raises UndefinedFunctionError when adapter is not a module" do
      assert_raise UndefinedFunctionError, fn ->
        Blink.copy_to_table([], "users", TestRepo, adapter: :not_a_module)
      end
    end

    test "calls the adapter when it properly implements call/4" do
      # Define a valid adapter for testing
      defmodule ValidAdapter do
        @behaviour Blink.Adapter

        @impl true
        def call(_items, _table_name, _repo, _opts) do
          {:ok, :test_result}
        end
      end

      assert {:ok, :test_result} =
               Blink.copy_to_table([], "users", TestRepo, adapter: Blink.AdapterTest.ValidAdapter)
    end
  end
end
