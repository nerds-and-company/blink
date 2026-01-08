defmodule Blink.JSONTest do
  use ExUnit.Case, async: true

  @fixtures_path Path.expand("../fixtures", __DIR__)

  describe "from_json/2" do
    test "reads a JSON file and returns a list of maps" do
      path = Path.join(@fixtures_path, "users.json")

      result = Blink.from_json(path)

      assert length(result) == 3

      assert [
               %{"id" => 1, "name" => "Alice", "email" => "alice@example.com", "age" => 30},
               %{"id" => 2, "name" => "Bob", "email" => "bob@example.com", "age" => 25},
               %{
                 "id" => 3,
                 "name" => "Charlie",
                 "email" => "charlie@example.com",
                 "age" => 35
               }
             ] = result
    end

    test "returns an empty list for empty JSON array" do
      path = Path.join(@fixtures_path, "empty.json")

      result = Blink.from_json(path)

      assert result == []
    end

    test "applies custom transformation when transform option provided" do
      path = Path.join(@fixtures_path, "users.json")

      result =
        Blink.from_json(path,
          transform: fn row ->
            Map.update!(row, "name", &String.upcase/1)
          end
        )

      assert length(result) == 3

      assert [
               %{"id" => 1, "name" => "ALICE", "email" => "alice@example.com", "age" => 30},
               %{"id" => 2, "name" => "BOB", "email" => "bob@example.com", "age" => 25},
               %{"id" => 3, "name" => "CHARLIE", "email" => "charlie@example.com", "age" => 35}
             ] = result
    end

    test "raises when file does not exist" do
      assert_raise File.Error, fn ->
        Blink.from_json("nonexistent.json")
      end
    end

    test "raises when transform is not a function" do
      path = Path.join(@fixtures_path, "users.json")

      assert_raise ArgumentError,
                   ":transform option must be a function that takes 1 argument",
                   fn ->
                     Blink.from_json(path, transform: "not a function")
                   end
    end

    test "raises when transform has wrong arity" do
      path = Path.join(@fixtures_path, "users.json")

      assert_raise ArgumentError,
                   ":transform option must be a function that takes 1 argument",
                   fn ->
                     Blink.from_json(path, transform: fn _a, _b -> %{} end)
                   end
    end

    test "raises when JSON root is not an array" do
      path = Path.join(@fixtures_path, "invalid_root.json")

      assert_raise ArgumentError,
                   ~r/JSON file must contain an array at root level/,
                   fn ->
                     Blink.from_json(path)
                   end
    end

    test "raises when JSON array contains non-objects" do
      path = Path.join(@fixtures_path, "invalid_items.json")

      assert_raise ArgumentError,
                   ~r/JSON file must contain an array of objects/,
                   fn ->
                     Blink.from_json(path)
                   end
    end
  end
end
