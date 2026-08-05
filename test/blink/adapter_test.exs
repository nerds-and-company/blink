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

    test "normalizes an atom table name to a string before calling the adapter" do
      defmodule NameRecordingAdapter do
        @behaviour Blink.Adapter

        @impl true
        def call(_rows, table_name, _repo, _opts), do: {:ok, table_name}
      end

      assert {:ok, "users"} =
               Blink.copy_to_table([], :users, TestRepo,
                 adapter: Blink.AdapterTest.NameRecordingAdapter
               )
    end

    # Adapters own their option vocabulary, so options Blink does not know
    # about must reach the adapter untouched — global, per-table, and merged.
    test "forwards adapter-specific options untouched through run/3" do
      defmodule RecordingAdapter do
        @behaviour Blink.Adapter

        @impl true
        def call(_rows, table_name, _repo, opts) do
          send(Keyword.fetch!(opts, :notify), {:copied, table_name, opts})
          :ok
        end
      end

      seeder =
        Blink.Seeder.new()
        |> Blink.Seeder.with_table("users", fn _, _ -> [] end)
        |> Blink.Seeder.with_table("posts", fn _, _ -> [] end, compression: :lz4)

      assert :ok =
               Blink.Seeder.run(seeder, TestRepo,
                 adapter: Blink.AdapterTest.RecordingAdapter,
                 notify: self(),
                 compression: :zstd
               )

      assert_received {:copied, "users", opts}
      assert opts[:compression] == :zstd
      refute Keyword.has_key?(opts, :adapter)

      assert_received {:copied, "posts", opts}
      assert opts[:compression] == :lz4
    end
  end
end
