defmodule Blink.StoreTest do
  use ExUnit.Case, async: true

  alias Blink.Store

  @moduletag capture_log: true

  describe "new/0" do
    test "returns an empty Store" do
      assert %Store{tables: %{}, table_order: [], context: %{}} = Store.new()
    end
  end

  describe "add_table/3" do
    test "adds table data to the store" do
      store =
        Store.new()
        |> Store.add_table("users", fn _store, _table_name ->
          [%{id: 1, name: "Alice"}]
        end)

      assert %{"users" => [%{id: 1, name: "Alice"}]} = store.tables
    end

    test "appends table name to table_order" do
      store =
        Store.new()
        |> Store.add_table("users", fn _, _ -> [] end)
        |> Store.add_table("posts", fn _, _ -> [] end)

      assert ["users", "posts"] = store.table_order
    end

    test "accepts atom keys" do
      store =
        Store.new()
        |> Store.add_table(:users, fn _, _ -> [] end)

      assert %{"users" => []} = store.tables
      assert ["users"] = store.table_order
    end

    test "passes store and table_name to builder function" do
      Store.new()
      |> Store.add_table("users", fn store, table_name ->
        assert %Store{} = store
        assert "users" = table_name
        []
      end)
    end

    test "raises if table name already exists" do
      store =
        Store.new()
        |> Store.add_table("users", fn _, _ -> [] end)

      assert_raise ArgumentError, ~r/key already exists in `:tables`/, fn ->
        Store.add_table(store, "users", fn _, _ -> [] end)
      end
    end

    test "raises if table name exists as different type (atom vs string)" do
      store =
        Store.new()
        |> Store.add_table(:users, fn _, _ -> [] end)

      assert_raise ArgumentError, ~r/key already exists in `:tables`/, fn ->
        Store.add_table(store, "users", fn _, _ -> [] end)
      end
    end
  end

  describe "add_context/3" do
    test "adds context data to the store" do
      store =
        Store.new()
        |> Store.add_context("ids", fn _store, _key ->
          [1, 2, 3]
        end)

      assert %{"ids" => [1, 2, 3]} = store.context
    end

    test "accepts atom keys" do
      store =
        Store.new()
        |> Store.add_context(:ids, fn _, _ -> [1, 2, 3] end)

      assert %{"ids" => [1, 2, 3]} = store.context
    end

    test "passes store and key to builder function" do
      Store.new()
      |> Store.add_context("data", fn store, key ->
        assert %Store{} = store
        assert "data" = key
        []
      end)
    end

    test "raises if context key already exists" do
      store =
        Store.new()
        |> Store.add_context("data", fn _, _ -> [] end)

      assert_raise ArgumentError, ~r/key already exists in `:context`/, fn ->
        Store.add_context(store, "data", fn _, _ -> [] end)
      end
    end

    test "raises if context key exists as different type (atom vs string)" do
      store =
        Store.new()
        |> Store.add_context(:data, fn _, _ -> [] end)

      assert_raise ArgumentError, ~r/key already exists in `:context`/, fn ->
        Store.add_context(store, "data", fn _, _ -> [] end)
      end
    end
  end
end
