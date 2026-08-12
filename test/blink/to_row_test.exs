defmodule Blink.ToRowTest do
  use ExUnit.Case, async: true

  import Blink, only: [to_row: 1, to_row: 2, to_rows: 1, to_rows: 2]

  alias BlinkTest.Repo

  defmodule Product do
    use Ecto.Schema

    schema "products" do
      field :name, :string
      field :price, :integer
      field :tag, :string, virtual: true
      belongs_to :user, Blink.ToRowTest.User
    end
  end

  defmodule Token do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "tokens" do
      field :value, :string
    end
  end

  defmodule Membership do
    use Ecto.Schema

    @primary_key false
    schema "memberships" do
      field :user_id, :integer, primary_key: true
      field :group_id, :integer, primary_key: true
      field :role, :string
    end
  end

  defmodule SerialItem do
    use Ecto.Schema

    schema "serial_items" do
      field :position, :integer
    end
  end

  describe "to_row/2" do
    test "keeps only persisted fields and drops the primary key by default" do
      row = to_row(%Product{name: "Widget", price: 5, tag: "internal"})

      assert row == %{name: "Widget", price: 5, user_id: nil}
    end

    test "id: :keep keeps the struct's primary key" do
      row = to_row(%Token{id: "0b1e9c1e", value: "t"}, id: :keep)

      assert row == %{id: "0b1e9c1e", value: "t"}
    end

    test "a literal id is set as the primary key" do
      row = to_row(%Product{name: "Widget"}, id: 42)

      assert row.id == 42
    end

    test "a literal id on a composite primary key raises" do
      assert_raise ArgumentError, ~r/composite|not a single field/, fn ->
        to_row(%Membership{user_id: 1, group_id: 2}, id: 3)
      end
    end

    test "id: :database drops every composite primary key field" do
      row = to_row(%Membership{user_id: 1, group_id: 2, role: "admin"})

      assert row == %{role: "admin"}
    end

    test "a non-schema struct raises" do
      assert_raise ArgumentError, ~r/expected an Ecto schema struct/, fn ->
        to_row(~U[2026-01-01 00:00:00Z])
      end
    end

    test "a plain map raises" do
      assert_raise ArgumentError, ~r/expected an Ecto schema struct/, fn ->
        to_row(%{name: "Widget"})
      end
    end

    test "an unknown option raises" do
      assert_raise ArgumentError, fn -> to_row(%Product{}, primary_key: :drop) end
    end
  end

  describe "to_rows/2" do
    test "converts every struct with the shared id policy" do
      rows = to_rows([%Product{name: "A"}, %Product{name: "B"}])

      assert rows == [
               %{name: "A", price: nil, user_id: nil},
               %{name: "B", price: nil, user_id: nil}
             ]
    end

    test "a literal id raises" do
      assert_raise ArgumentError, ~r/use to_row\/2 for per-row ids/, fn ->
        to_rows([%Product{}], id: 42)
      end
    end

    test "drop_nil_columns: true drops columns that are nil in every row" do
      rows =
        to_rows([%Product{name: "A"}, %Product{name: "B", price: 3}], drop_nil_columns: true)

      assert rows == [%{name: "A", price: nil}, %{name: "B", price: 3}]
    end

    test "an empty list stays empty" do
      assert to_rows([], drop_nil_columns: true) == []
    end
  end

  test "converted rows copy cleanly with database-assigned ids" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    rows = Enum.map(1..3, fn n -> to_row(%SerialItem{position: n}) end)

    assert :ok = Blink.copy_to_table(rows, "serial_items", Repo)
  end
end
