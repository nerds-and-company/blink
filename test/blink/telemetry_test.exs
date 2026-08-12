defmodule Blink.TelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BlinkTest.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp attach(events) do
    ref = :telemetry_test.attach_event_handlers(self(), events)
    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  describe "build events" do
    test "with_table and with_context emit build spans" do
      ref = attach([[:blink, :build, :start], [:blink, :build, :stop]])

      Blink.Seeder.new()
      |> Blink.Seeder.with_table("users", fn _seeder, _name -> [%{id: 1}] end)
      |> Blink.Seeder.with_context(:now, fn _seeder, _key -> :value end)

      assert_received {[:blink, :build, :start], ^ref, %{system_time: _},
                       %{callback: :table, key: "users"}}

      assert_received {[:blink, :build, :stop], ^ref, %{duration: _},
                       %{callback: :table, key: "users"}}

      assert_received {[:blink, :build, :stop], ^ref, %{duration: _},
                       %{callback: :context, key: :now}}
    end

    test "a raising builder emits an exception event and re-raises" do
      ref = attach([[:blink, :build, :exception]])

      assert_raise RuntimeError, "boom", fn ->
        Blink.Seeder.with_table(Blink.Seeder.new(), "users", fn _seeder, _name ->
          raise "boom"
        end)
      end

      assert_received {[:blink, :build, :exception], ^ref, %{duration: _},
                       %{callback: :table, key: "users"}}
    end
  end

  describe "run events" do
    test "run/3 emits a span with repo, tables, and atomicity" do
      ref = attach([[:blink, :run, :start], [:blink, :run, :stop]])

      Blink.Seeder.new()
      |> Blink.put_table("users", [%{id: 1, name: "Alice"}])
      |> Blink.Seeder.run(Repo)

      assert_received {[:blink, :run, :start], ^ref, %{system_time: _},
                       %{repo: BlinkTest.Repo, tables: ["users"], atomic: true}}

      assert_received {[:blink, :run, :stop], ^ref, %{duration: _}, %{tables: ["users"]}}
    end

    test "run/3 emits an exception event when the copy fails" do
      ref = attach([[:blink, :run, :exception]])

      seeder = Blink.put_table(Blink.Seeder.new(), "users", [%{id: 1}, %{nope: 2}])

      assert_raise Blink.RowError, fn ->
        Blink.Seeder.run(seeder, Repo)
      end

      assert_received {[:blink, :run, :exception], ^ref, %{duration: _},
                       %{kind: :error, reason: %Blink.RowError{}}}
    end
  end

  describe "copy events" do
    test "the copy :stop event reports the row count" do
      ref = attach([[:blink, :copy, :stop]])

      rows = Enum.map(1..5, &%{id: &1})

      assert :ok = Blink.copy_to_table(rows, "users", Repo, batch_size: 2)

      assert_received {[:blink, :copy, :stop], ^ref, %{row_count: 5, duration: _},
                       %{table_name: "users", batch_size: 2}}
    end

    test "a failed copy emits an exception event instead of :stop" do
      ref = attach([[:blink, :copy, :stop], [:blink, :copy, :exception]])

      assert_raise Blink.RowError, fn ->
        Blink.copy_to_table([%{id: 1}, %{nope: 2}], "users", Repo)
      end

      assert_received {[:blink, :copy, :exception], ^ref, %{duration: _},
                       %{table_name: "users", kind: :error, reason: %Blink.RowError{}}}

      refute_received {[:blink, :copy, :stop], ^ref, _, _}
    end
  end

  describe "attach_default_logger/1" do
    test "logs run start and stop" do
      assert :ok = Blink.Telemetry.attach_default_logger()
      on_exit(fn -> Blink.Telemetry.detach_default_logger() end)

      log =
        capture_log(fn ->
          Blink.Seeder.new()
          |> Blink.put_table("users", [%{id: 1, name: "Alice"}])
          |> Blink.Seeder.run(Repo)
        end)

      assert log =~ "Seeding BlinkTest.Repo (1 table)..."
      assert log =~ ~r/Seeded BlinkTest\.Repo \(1 table\) in \d+ ms/

      # Every attached event must produce its line — a clause missing for an
      # attached event would crash the handler and detach the whole logger.
      assert log =~ ~s(Built table "users")
      assert log =~ ~r/Copied 1 rows into "users"/
    end

    test "logs a failed build as an error" do
      assert :ok = Blink.Telemetry.attach_default_logger()
      on_exit(fn -> Blink.Telemetry.detach_default_logger() end)

      log =
        capture_log(fn ->
          assert_raise RuntimeError, "boom", fn ->
            Blink.Seeder.with_table(Blink.Seeder.new(), "users", fn _seeder, _name ->
              raise "boom"
            end)
          end
        end)

      assert log =~ ~s(Building table "users" failed)
      assert log =~ "boom"
    end

    test "logs a failed copy as an error" do
      assert :ok = Blink.Telemetry.attach_default_logger()
      on_exit(fn -> Blink.Telemetry.detach_default_logger() end)

      log =
        capture_log(fn ->
          assert_raise Blink.RowError, fn ->
            Blink.copy_to_table([%{id: 1}, %{nope: 2}], "users", Repo)
          end
        end)

      assert log =~ ~s(Copying into "users" failed)
      assert log =~ "Blink.RowError"
    end

    test "logs a failed run as an error" do
      assert :ok = Blink.Telemetry.attach_default_logger()
      on_exit(fn -> Blink.Telemetry.detach_default_logger() end)

      seeder = Blink.put_table(Blink.Seeder.new(), "users", [%{id: 1}, %{nope: 2}])

      log =
        capture_log(fn ->
          assert_raise Blink.RowError, fn -> Blink.Seeder.run(seeder, Repo) end
        end)

      assert log =~ "Seeding BlinkTest.Repo failed"
      assert log =~ "Blink.RowError"
    end

    test "attaches once and detaches" do
      assert :ok = Blink.Telemetry.attach_default_logger()
      assert {:error, :already_exists} = Blink.Telemetry.attach_default_logger()
      assert :ok = Blink.Telemetry.detach_default_logger()
      assert {:error, :not_found} = Blink.Telemetry.detach_default_logger()
    end
  end
end
