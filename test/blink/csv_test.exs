defmodule Blink.CSVTest do
  use ExUnit.Case, async: true

  @fixtures_path Path.expand("../fixtures", __DIR__)

  describe "from_csv/2" do
    test "reads a CSV file and returns a list of maps with string keys" do
      path = Path.join(@fixtures_path, "users.csv")

      result = Blink.from_csv(path)

      assert length(result) == 3

      assert [
               %{"id" => "1", "name" => "Alice", "email" => "alice@example.com", "age" => "30"},
               %{"id" => "2", "name" => "Bob", "email" => "bob@example.com", "age" => "25"},
               %{
                 "id" => "3",
                 "name" => "Charlie",
                 "email" => "charlie@example.com",
                 "age" => "35"
               }
             ] = result
    end

    test "returns an empty list for empty CSV file" do
      path = Path.join(@fixtures_path, "empty.csv")

      result = Blink.from_csv(path)

      assert result == []
    end

    test "applies custom transformation when transform option provided" do
      path = Path.join(@fixtures_path, "users.csv")

      result =
        Blink.from_csv(path,
          transform: fn row ->
            row
            |> Map.update!("id", &String.to_integer/1)
            |> Map.update!("age", &String.to_integer/1)
          end
        )

      assert length(result) == 3

      assert [
               %{"id" => 1, "name" => "Alice", "email" => "alice@example.com", "age" => 30},
               %{"id" => 2, "name" => "Bob", "email" => "bob@example.com", "age" => 25},
               %{"id" => 3, "name" => "Charlie", "email" => "charlie@example.com", "age" => 35}
             ] = result
    end

    test "raises when file does not exist" do
      assert_raise File.Error, fn ->
        Blink.from_csv("nonexistent.csv")
      end
    end

    test "raises when transform is not a function" do
      path = Path.join(@fixtures_path, "users.csv")

      assert_raise ArgumentError,
                   ":transform option must be a function that takes 1 argument",
                   fn ->
                     Blink.from_csv(path, transform: "not a function")
                   end
    end

    test "raises when transform has wrong arity" do
      path = Path.join(@fixtures_path, "users.csv")

      assert_raise ArgumentError,
                   ":transform option must be a function that takes 1 argument",
                   fn ->
                     Blink.from_csv(path, transform: fn _a, _b -> %{} end)
                   end
    end

    test "reads CSV without headers when headers option provided" do
      path = Path.join(@fixtures_path, "users_no_headers.csv")

      result = Blink.from_csv(path, headers: ["id", "name", "email", "age"])

      assert length(result) == 3

      assert [
               %{"id" => "1", "name" => "Alice", "email" => "alice@example.com", "age" => "30"},
               %{"id" => "2", "name" => "Bob", "email" => "bob@example.com", "age" => "25"},
               %{
                 "id" => "3",
                 "name" => "Charlie",
                 "email" => "charlie@example.com",
                 "age" => "35"
               }
             ] = result
    end

    test "can combine headers and transform options" do
      path = Path.join(@fixtures_path, "users_no_headers.csv")

      result =
        Blink.from_csv(path,
          headers: ["id", "name", "email", "age"],
          transform: fn row ->
            row
            |> Map.update!("id", &String.to_integer/1)
            |> Map.update!("age", &String.to_integer/1)
          end
        )

      assert length(result) == 3

      assert [
               %{"id" => 1, "name" => "Alice", "email" => "alice@example.com", "age" => 30},
               %{"id" => 2, "name" => "Bob", "email" => "bob@example.com", "age" => 25},
               %{"id" => 3, "name" => "Charlie", "email" => "charlie@example.com", "age" => 35}
             ] = result
    end

    test "raises when headers option is invalid" do
      path = Path.join(@fixtures_path, "users.csv")

      assert_raise ArgumentError,
                   ~r/:headers option must be a list of header names or :infer/,
                   fn ->
                     Blink.from_csv(path, headers: "invalid")
                   end
    end
  end
end
