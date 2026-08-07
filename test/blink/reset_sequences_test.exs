defmodule Blink.ResetSequencesTest do
  # async: false — sequences are non-transactional, so the sandbox cannot
  # isolate them; each test pins its sequence to a known value first.
  use ExUnit.Case, async: false

  alias BlinkTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp pin_sequence(table) do
    Repo.query!("SELECT setval(pg_get_serial_sequence('#{table}', 'id'), 1, false)")
  end

  defp next_id(table) do
    %{rows: [[id]]} = Repo.query!("INSERT INTO #{table} (position) VALUES (0) RETURNING id")
    id
  end

  test "advances a serial primary key past the seeded ids" do
    pin_sequence("serial_items")
    rows = Enum.map(1..3, &%{id: &1, position: &1})

    assert :ok = Blink.copy_to_table(rows, "serial_items", Repo, reset_sequences: true)
    assert next_id("serial_items") == 4
  end

  test "advances an identity primary key past the seeded ids" do
    pin_sequence("identity_items")
    rows = Enum.map(1..7, &%{id: &1, position: &1})

    assert :ok = Blink.copy_to_table(rows, "identity_items", Repo, reset_sequences: true)
    assert next_id("identity_items") == 8
  end

  test "without the option the next insert collides with a seeded row" do
    pin_sequence("serial_items")
    rows = Enum.map(1..3, &%{id: &1, position: &1})

    assert :ok = Blink.copy_to_table(rows, "serial_items", Repo)

    assert_raise Postgrex.Error, ~r/unique_violation/, fn ->
      next_id("serial_items")
    end
  end

  test "a primary key without a sequence is skipped" do
    assert :ok =
             Blink.copy_to_table([%{id: 1, name: "Alice"}], "users", Repo, reset_sequences: true)
  end

  test "run/3 forwards the option to every table" do
    pin_sequence("serial_items")
    pin_sequence("identity_items")

    Blink.Seeder.new()
    |> Blink.put_table("serial_items", [%{id: 1, position: 1}])
    |> Blink.put_table("identity_items", [%{id: 5, position: 5}])
    |> Blink.Seeder.run(Repo, reset_sequences: true)

    assert next_id("serial_items") == 2
    assert next_id("identity_items") == 6
  end

  test "can be enabled for a single table" do
    pin_sequence("serial_items")
    pin_sequence("identity_items")

    Blink.Seeder.new()
    |> Blink.put_table("serial_items", [%{id: 3, position: 3}], reset_sequences: true)
    |> Blink.put_table("identity_items", [%{id: 3, position: 3}])
    |> Blink.Seeder.run(Repo)

    assert next_id("serial_items") == 4
    assert next_id("identity_items") == 1
  end

  test "rejects a non-boolean value" do
    assert_raise ArgumentError, fn ->
      Blink.copy_to_table([%{id: 1}], "users", Repo, reset_sequences: "yes")
    end
  end
end
