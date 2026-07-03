defmodule Blink.PutHelpersTest do
  use ExUnit.Case, async: true

  alias Blink.Seeder

  describe "put_context/3" do
    test "stores the value under the key without a context/2 callback" do
      seeder = Blink.put_context(Seeder.new(), :now, "2024-01-01")
      assert %{now: "2024-01-01"} = seeder.context
    end

    test "accepts string keys" do
      seeder = Blink.put_context(Seeder.new(), "ids", [1, 2, 3])
      assert %{"ids" => [1, 2, 3]} = seeder.context
    end

    test "raises if the context key already exists" do
      seeder = Blink.put_context(Seeder.new(), :dup, 1)

      assert_raise ArgumentError, ~r/key already exists in `:context`/, fn ->
        Blink.put_context(seeder, :dup, 2)
      end
    end
  end

  describe "put_table/3 and put_table/4" do
    test "put_table/4 forwards per-table options to with_table" do
      seeder = Blink.put_table(Seeder.new(), "users", [], batch_size: 500, concurrency: 2)
      assert Enum.sort(seeder.table_opts["users"]) == [batch_size: 500, concurrency: 2]
    end

    test "put_table/4 rejects options that are not per-table tuning options" do
      assert_raise ArgumentError, fn ->
        Blink.put_table(Seeder.new(), "users", [], atomic: true)
      end
    end

    test "stores the rows and appends to table_order without a table/2 callback" do
      rows = [%{id: 1, name: "Alice"}]
      seeder = Blink.put_table(Seeder.new(), "users", rows)

      assert %{"users" => ^rows} = seeder.tables
      assert ["users"] = seeder.table_order
    end

    test "accepts atom keys and preserves order across calls" do
      seeder =
        Seeder.new()
        |> Blink.put_table(:users, [%{id: 1}])
        |> Blink.put_table(:posts, [%{id: 1}])

      assert [:users, :posts] = seeder.table_order
    end

    test "raises if the table already exists" do
      seeder = Blink.put_table(Seeder.new(), "users", [])

      assert_raise ArgumentError, ~r/key already exists in `:tables`/, fn ->
        Blink.put_table(seeder, "users", [])
      end
    end

    test "stores a stream without materializing it" do
      stream = Stream.map([1], fn _ -> raise "stream was materialized" end)
      seeder = Blink.put_table(Seeder.new(), "users", stream)

      assert %Stream{} = seeder.tables["users"]
    end
  end

  describe "put_context/2 (multiple keys)" do
    test "adds every pair in a keyword list" do
      seeder = Blink.put_context(Seeder.new(), user_id: 7, project_indices: [1, 2])
      assert %{user_id: 7, project_indices: [1, 2]} = seeder.context
    end

    test "raises when a key is repeated within the list" do
      assert_raise ArgumentError, ~r/key already exists in `:context`/, fn ->
        Blink.put_context(Seeder.new(), dup: 1, dup: 2)
      end
    end
  end

  describe "put_table/2 (multiple tables)" do
    test "adds every table in order" do
      seeder = Blink.put_table(Seeder.new(), users: [%{id: 1}], posts: [%{id: 2}])

      assert %{users: [%{id: 1}], posts: [%{id: 2}]} = seeder.tables
      assert [:users, :posts] = seeder.table_order
    end

    test "raises when a table name is repeated within the list" do
      assert_raise ArgumentError, ~r/key already exists in `:tables`/, fn ->
        Blink.put_table(Seeder.new(), dup: [], dup: [])
      end
    end
  end

  describe "imported into `use Blink` modules" do
    test "every arity is callable unqualified" do
      defmodule Importer do
        use Blink

        def build do
          new()
          |> put_table(users: [%{id: 1, name: "Alice"}])
          |> put_table("posts", [%{id: 1}], batch_size: 10)
          |> put_context(count: 1)
          |> put_context(:flag, true)
        end
      end

      seeder = Importer.build()

      assert %{"posts" => [%{id: 1}], users: [%{id: 1, name: "Alice"}]} = seeder.tables
      assert [:users, "posts"] = seeder.table_order
      assert %{count: 1, flag: true} = seeder.context
      assert [batch_size: 10] = seeder.table_opts["posts"]

      :code.delete(Importer)
      :code.purge(Importer)
    end
  end
end
