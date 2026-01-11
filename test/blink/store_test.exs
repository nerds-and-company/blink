defmodule Blink.StoreTest do
  use ExUnit.Case, async: true

  alias Blink.Store

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

      assert %{users: []} = store.tables
      assert [:users] = store.table_order
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

      assert %{ids: [1, 2, 3]} = store.context
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

  describe "Access behaviour" do
    test "bracket syntax returns nil for invalid keys" do
      store = Store.new()

      assert nil == store[:invalid]
    end

    test "get_in/2" do
      store =
        Store.new()
        |> Store.add_table("users", fn _, _ -> [%{id: 1}] end)

      assert [%{id: 1}] = get_in(store, [:tables, "users"])
    end

    test "put_in/3" do
      store = Store.new()

      new_store = put_in(store, [:tables, "users"], [%{id: 1}])

      assert %{"users" => [%{id: 1}]} = new_store.tables
    end

    test "update_in/3" do
      store =
        Store.new()
        |> Store.add_table("users", fn _, _ -> [%{id: 1}] end)

      new_store = update_in(store, [:tables, "users"], fn users -> users ++ [%{id: 2}] end)

      assert [%{id: 1}, %{id: 2}] = Map.fetch!(new_store.tables, "users")
    end

    test "pop_in/2 resets :tables to empty map" do
      store =
        Store.new()
        |> Store.add_table("users", fn _, _ -> [] end)

      {tables, new_store} = pop_in(store, [:tables])

      assert %{"users" => []} = tables
      assert %{} = new_store.tables
    end

    test "pop_in/2 resets :table_order to empty list" do
      store =
        Store.new()
        |> Store.add_table("users", fn _, _ -> [] end)

      {table_order, new_store} = pop_in(store, [:table_order])

      assert ["users"] = table_order
      assert [] = new_store.table_order
    end

    test "pop_in/2 resets :context to empty map" do
      store =
        Store.new()
        |> Store.add_context("data", fn _, _ -> [1, 2, 3] end)

      {context, new_store} = pop_in(store, [:context])

      assert %{"data" => [1, 2, 3]} = context
      assert %{} = new_store.context
    end

    test "pop_in/2 returns {nil, store} for invalid keys" do
      store = Store.new()

      assert {nil, ^store} = pop_in(store, [:invalid])
    end
  end
end
