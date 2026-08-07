defmodule Blink.FetchRowTest do
  use ExUnit.Case, async: true

  alias Blink.Seeder

  @users [
    %{id: 1, email: "alice@example.com", role: :admin},
    %{id: 2, email: "bob@example.com", role: :member},
    %{id: 3, email: "carol@example.com", role: :member}
  ]

  defp seeder, do: Blink.put_table(Seeder.new(), "users", @users)

  describe "fetch_row!/3" do
    test "returns the first row matching a clause" do
      assert %{id: 2} = Blink.fetch_row!(seeder(), "users", email: "bob@example.com")
      assert %{id: 2} = Blink.fetch_row!(seeder(), "users", role: :member)
    end

    test "all clauses must match" do
      assert %{id: 3} =
               Blink.fetch_row!(seeder(), "users", role: :member, email: "carol@example.com")
    end

    test "raises naming the table and clauses when no row matches" do
      error =
        assert_raise ArgumentError, fn ->
          Blink.fetch_row!(seeder(), "users", email: "nobody@example.com")
        end

      assert error.message =~ ~s(no row in table "users")
      assert error.message =~ "nobody@example.com"
    end

    test "raises naming the declared tables for an undeclared table" do
      error =
        assert_raise ArgumentError, fn ->
          Blink.fetch_row!(seeder(), "missing", id: 1)
        end

      assert error.message =~ ~s(table "missing" has not been declared)
      assert error.message =~ ~s(["users"])
    end

    test "atom and string table names are interchangeable" do
      atom_declared = Blink.put_table(Seeder.new(), :users, @users)

      assert %{id: 1} = Blink.fetch_row!(atom_declared, "users", id: 1)
      assert %{id: 1} = Blink.fetch_row!(seeder(), :users, id: 1)
    end

    test "is imported by use Blink" do
      defmodule FetchDummy do
        use Blink

        def call do
          new()
          |> put_table("users", [%{id: 1, name: "Alice"}])
          |> fetch_row!("users", name: "Alice")
        end
      end

      assert %{id: 1} = FetchDummy.call()
    end
  end
end
