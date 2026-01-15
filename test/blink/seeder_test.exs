defmodule Blink.SeederTest do
  use ExUnit.Case, async: true

  alias Blink.Seeder

  describe "new/0" do
    test "returns an empty Seeder" do
      assert %Seeder{tables: %{}, table_order: [], context: %{}} = Seeder.new()
    end
  end

  describe "with_table/3" do
    test "adds table data to the seeder" do
      seeder =
        Seeder.new()
        |> Seeder.with_table("users", fn _seeder, _table_name ->
          [%{id: 1, name: "Alice"}]
        end)

      assert %{"users" => [%{id: 1, name: "Alice"}]} = seeder.tables
    end

    test "appends table name to table_order" do
      seeder =
        Seeder.new()
        |> Seeder.with_table("users", fn _, _ -> [] end)
        |> Seeder.with_table("posts", fn _, _ -> [] end)

      assert ["users", "posts"] = seeder.table_order
    end

    test "accepts atom keys" do
      seeder =
        Seeder.new()
        |> Seeder.with_table(:users, fn _, _ -> [] end)

      assert %{users: []} = seeder.tables
      assert [:users] = seeder.table_order
    end

    test "passes seeder and table_name to builder function" do
      Seeder.new()
      |> Seeder.with_table("users", fn seeder, table_name ->
        assert %Seeder{} = seeder
        assert "users" = table_name
        []
      end)
    end

    test "raises if table name already exists" do
      seeder =
        Seeder.new()
        |> Seeder.with_table("users", fn _, _ -> [] end)

      assert_raise ArgumentError, ~r/key already exists in `:tables`/, fn ->
        Seeder.with_table(seeder, "users", fn _, _ -> [] end)
      end
    end

    test "raises if table name exists as different type (atom vs string)" do
      seeder =
        Seeder.new()
        |> Seeder.with_table(:users, fn _, _ -> [] end)

      assert_raise ArgumentError, ~r/key already exists in `:tables`/, fn ->
        Seeder.with_table(seeder, "users", fn _, _ -> [] end)
      end
    end
  end

  describe "with_context/3" do
    test "loads context data into the seeder" do
      seeder =
        Seeder.new()
        |> Seeder.with_context("ids", fn _seeder, _key ->
          [1, 2, 3]
        end)

      assert %{"ids" => [1, 2, 3]} = seeder.context
    end

    test "accepts atom keys" do
      seeder =
        Seeder.new()
        |> Seeder.with_context(:ids, fn _, _ -> [1, 2, 3] end)

      assert %{ids: [1, 2, 3]} = seeder.context
    end

    test "passes seeder and key to builder function" do
      Seeder.new()
      |> Seeder.with_context("data", fn seeder, key ->
        assert %Seeder{} = seeder
        assert "data" = key
        []
      end)
    end

    test "raises if context key already exists" do
      seeder =
        Seeder.new()
        |> Seeder.with_context("data", fn _, _ -> [] end)

      assert_raise ArgumentError, ~r/key already exists in `:context`/, fn ->
        Seeder.with_context(seeder, "data", fn _, _ -> [] end)
      end
    end

    test "raises if context key exists as different type (atom vs string)" do
      seeder =
        Seeder.new()
        |> Seeder.with_context(:data, fn _, _ -> [] end)

      assert_raise ArgumentError, ~r/key already exists in `:context`/, fn ->
        Seeder.with_context(seeder, "data", fn _, _ -> [] end)
      end
    end
  end

  describe "Access behaviour" do
    test "bracket syntax returns nil for invalid keys" do
      seeder = Seeder.new()

      assert nil == seeder[:invalid]
    end

    test "get_in/2" do
      seeder =
        Seeder.new()
        |> Seeder.with_table("users", fn _, _ -> [%{id: 1}] end)

      assert [%{id: 1}] = get_in(seeder, [:tables, "users"])
    end

    test "put_in/3" do
      seeder = Seeder.new()

      new_seeder = put_in(seeder, [:tables, "users"], [%{id: 1}])

      assert %{"users" => [%{id: 1}]} = new_seeder.tables
    end

    test "update_in/3" do
      seeder =
        Seeder.new()
        |> Seeder.with_table("users", fn _, _ -> [%{id: 1}] end)

      new_seeder = update_in(seeder, [:tables, "users"], fn users -> users ++ [%{id: 2}] end)

      assert [%{id: 1}, %{id: 2}] = Map.fetch!(new_seeder.tables, "users")
    end

    test "pop_in/2 resets :tables to empty map" do
      seeder =
        Seeder.new()
        |> Seeder.with_table("users", fn _, _ -> [] end)

      {tables, new_seeder} = pop_in(seeder, [:tables])

      assert %{"users" => []} = tables
      assert %{} = new_seeder.tables
    end

    test "pop_in/2 resets :table_order to empty list" do
      seeder =
        Seeder.new()
        |> Seeder.with_table("users", fn _, _ -> [] end)

      {table_order, new_seeder} = pop_in(seeder, [:table_order])

      assert ["users"] = table_order
      assert [] = new_seeder.table_order
    end

    test "pop_in/2 resets :context to empty map" do
      seeder =
        Seeder.new()
        |> Seeder.with_context("data", fn _, _ -> [1, 2, 3] end)

      {context, new_seeder} = pop_in(seeder, [:context])

      assert %{"data" => [1, 2, 3]} = context
      assert %{} = new_seeder.context
    end

    test "pop_in/2 returns {nil, seeder} for invalid keys" do
      seeder = Seeder.new()

      assert {nil, ^seeder} = pop_in(seeder, [:invalid])
    end
  end
end
