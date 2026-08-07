defmodule Blink.RowValidationTest do
  use ExUnit.Case, async: true

  import Ecto.Query, warn: false

  alias BlinkTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "row key validation" do
    test "raises when a later row is missing a key" do
      rows = [%{id: 1, name: "Alice"}, %{id: 2}]

      error =
        assert_raise Blink.RowError, fn ->
          Blink.copy_to_table(rows, "users", Repo)
        end

      assert error.table_name == "users"
      assert error.index == 1
      assert error.missing == [:name]
      assert error.extra == []
    end

    test "raises when a later row has an extra key" do
      rows = [%{id: 1}, %{id: 2, name: "Bob"}]

      error =
        assert_raise Blink.RowError, fn ->
          Blink.copy_to_table(rows, "users", Repo)
        end

      assert error.missing == []
      assert error.extra == [:name]
    end

    test "a typo'd key reports as one missing and one extra key" do
      rows = [%{id: 1, name: "Alice"}, %{id: 2, nmae: "Bob"}]

      error =
        assert_raise Blink.RowError, fn ->
          Blink.copy_to_table(rows, "users", Repo)
        end

      assert error.missing == [:name]
      assert error.extra == [:nmae]
    end

    test "an atom key does not match a string key" do
      rows = [%{id: 1}, %{"id" => 2}]

      error =
        assert_raise Blink.RowError, fn ->
          Blink.copy_to_table(rows, "users", Repo)
        end

      assert error.missing == [:id]
      assert error.extra == ["id"]
    end

    test "reports the row's absolute index across batches" do
      rows = Enum.map(1..5, &%{id: &1}) ++ [%{id: 6, name: "x"}]

      error =
        assert_raise Blink.RowError, fn ->
          Blink.copy_to_table(rows, "users", Repo, batch_size: 2)
        end

      assert error.index == 5
    end

    test "message names the table, the index, and the differing keys" do
      rows = [%{id: 1, name: "Alice"}, %{id: 2, nmae: "Bob"}]

      error =
        assert_raise Blink.RowError, fn ->
          Blink.copy_to_table(rows, "users", Repo)
        end

      message = Exception.message(error)

      assert message =~ ~s(the row at index 1 of table "users")
      assert message =~ "is missing [:name]"
      assert message =~ "has extra keys [:nmae]"
      assert message =~ "column list from the keys of the first row"
    end

    test "an atomic copy that fails validation mid-copy leaves nothing behind" do
      rows = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}, %{id: 3}]

      assert_raise Blink.RowError, fn ->
        Blink.copy_to_table(rows, "users", Repo, batch_size: 2)
      end

      assert Repo.all(from(u in "users", select: u.id)) == []
    end

    test "raises on stream input" do
      rows =
        Stream.map(1..3, fn
          2 -> %{name: "no id"}
          i -> %{id: i}
        end)

      error =
        assert_raise Blink.RowError, fn ->
          Blink.copy_to_table(rows, "users", Repo)
        end

      assert error.index == 1
    end

    test "raises with atomic: false" do
      rows = [%{id: 1}, %{"id" => 2}]

      assert_raise Blink.RowError, fn ->
        Blink.copy_to_table(rows, "users", Repo, atomic: false)
      end
    end

    test "valid rows still insert" do
      rows = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

      assert :ok = Blink.copy_to_table(rows, "users", Repo)
      assert Repo.all(from(u in "users", select: u.id, order_by: u.id)) == [1, 2]
    end

    test "run/3 rolls back earlier tables when a later table fails validation" do
      seeder =
        Blink.Seeder.new()
        |> Blink.put_table("users", [%{id: 1, name: "Alice"}])
        |> Blink.put_table("posts", [%{id: 1, title: "One", user_id: 1}, %{id: 2, user_id: 1}])

      error =
        assert_raise Blink.RowError, fn ->
          Blink.Seeder.run(seeder, Repo)
        end

      assert error.table_name == "posts"
      assert error.missing == [:title]
      assert Repo.all(from(u in "users", select: u.id)) == []
    end
  end
end
