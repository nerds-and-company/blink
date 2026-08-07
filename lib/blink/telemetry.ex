defmodule Blink.Telemetry do
  @moduledoc """
  Telemetry events emitted by Blink, and a default logger built on them.

  Attach the default logger in your seed script to get progress logging
  without writing any timing code:

      Blink.Telemetry.attach_default_logger()
      MyApp.Seeder.call()

  ## Events

  ### Build events

  Table and context builders run when they are declared — `with_table/2` and
  `with_context/2` call your `table/2` or `context/2` clause immediately — so
  build time is reported per declaration, not as part of the run span below.

    * `[:blink, :build, :start]` — emitted when a builder starts.
      * Measurements: `:system_time`, `:monotonic_time`
      * Metadata: `:callback` (`:table` or `:context`), `:key` (the declared
        name)
    * `[:blink, :build, :stop]` — emitted when a builder returns.
      * Measurements: `:duration`, `:monotonic_time`
      * Metadata: as for `:start`
    * `[:blink, :build, :exception]` — emitted when a builder raises.
      * Measurements: `:duration`, `:monotonic_time`
      * Metadata: as for `:start`, plus `:kind`, `:reason`, and `:stacktrace`
        of the error

  A builder that returns a stream reports a near-zero duration here; its rows
  are produced during the copy instead.

  ### Run events

  A span around `Blink.Seeder.run/3` — the copy phase of the seed.

    * `[:blink, :run, :start]`
      * Measurements: `:system_time`, `:monotonic_time`
      * Metadata: `:repo`, `:tables` (declared names in insertion order),
        `:atomic`
    * `[:blink, :run, :stop]`
      * Measurements: `:duration`, `:monotonic_time`
      * Metadata: as for `:start`
    * `[:blink, :run, :exception]`
      * Measurements: `:duration`, `:monotonic_time`
      * Metadata: as for `:start`, plus `:kind`, `:reason`, `:stacktrace`

  ### Copy events

  Emitted by `Blink.Adapter.Postgres` for each table copied.

    * `[:blink, :copy, :start]` — emitted once per table, before the first
      batch is written.
      * Measurements: `:system_time`
      * Metadata: `:table_name`, `:batch_size`, `:concurrency`, `:timeout`,
        `:atomic`
    * `[:blink, :copy, :stop]` — emitted when the table's copy completes.
      A failed copy emits no `:stop` (and there is no copy exception event);
      failures surface through the surrounding `[:blink, :run]` span instead.
      * Measurements: `:duration`, `:row_count`
      * Metadata: as for `:start`

  Durations are in `:native` time units; convert with
  `System.convert_time_unit(duration, :native, :millisecond)`.

  ## Default logger

  `attach_default_logger/1` logs run start and stop at the given level
  (default `:info`), run and build failures at `:error`, and per-declaration
  build times and per-table copy times at `:debug`:

      [info] Seeding MyApp.Repo (3 tables)...
      [debug] Copied 1000 rows into "users" in 12 ms
      [info] Seeded MyApp.Repo (3 tables) in 87 ms
  """

  require Logger

  @handler_id "blink-default-logger"

  @doc """
  Attaches a logger to Blink's telemetry events.

  Run start and stop are logged at `level`; run and build failures at
  `:error`; build and copy completions at `:debug`. Returns
  `{:error, :already_exists}` if the logger is already attached.
  """
  @spec attach_default_logger(level :: Logger.level()) :: :ok | {:error, :already_exists}
  def attach_default_logger(level \\ :info) do
    events = [
      [:blink, :run, :start],
      [:blink, :run, :stop],
      [:blink, :run, :exception],
      [:blink, :build, :stop],
      [:blink, :build, :exception],
      [:blink, :copy, :stop]
    ]

    :telemetry.attach_many(@handler_id, events, &__MODULE__.handle_event/4, level)
  end

  @doc """
  Detaches the logger attached by `attach_default_logger/1`.

  Returns `{:error, :not_found}` if it is not attached.
  """
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_event([:blink, :run, :start], _measurements, metadata, level) do
    Logger.log(level, "Seeding #{inspect(metadata.repo)} (#{table_count(metadata)})...")
  end

  def handle_event([:blink, :run, :stop], measurements, metadata, level) do
    Logger.log(
      level,
      "Seeded #{inspect(metadata.repo)} (#{table_count(metadata)}) in #{ms(measurements)} ms"
    )
  end

  def handle_event([:blink, :run, :exception], measurements, metadata, _level) do
    Logger.error(
      "Seeding #{inspect(metadata.repo)} failed after #{ms(measurements)} ms: " <>
        Exception.format_banner(metadata.kind, metadata.reason, metadata.stacktrace)
    )
  end

  def handle_event([:blink, :build, :stop], measurements, metadata, _level) do
    Logger.debug("Built #{metadata.callback} #{inspect(metadata.key)} in #{ms(measurements)} ms")
  end

  def handle_event([:blink, :build, :exception], measurements, metadata, _level) do
    Logger.error(
      "Building #{metadata.callback} #{inspect(metadata.key)} failed after " <>
        "#{ms(measurements)} ms: " <>
        Exception.format_banner(metadata.kind, metadata.reason, metadata.stacktrace)
    )
  end

  def handle_event([:blink, :copy, :stop], measurements, metadata, _level) do
    Logger.debug(
      "Copied #{measurements.row_count} rows into #{inspect(metadata.table_name)} " <>
        "in #{ms(measurements)} ms"
    )
  end

  defp table_count(%{tables: tables}) do
    case length(tables) do
      1 -> "1 table"
      n -> "#{n} tables"
    end
  end

  defp ms(%{duration: duration}) do
    System.convert_time_unit(duration, :native, :millisecond)
  end
end
