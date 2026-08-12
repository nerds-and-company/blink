# Bulk Imports Outside Seeding

Blink's copy path is not seeding-specific. `Blink.copy_to_table/4` is a
general bulk-insert primitive — rows in, `COPY` out — and works just as well
for imports that run while your application serves traffic: ingesting an
uploaded CSV, syncing an external feed, backfilling a new table.

What changes is the environment. A seed runs against an idle, disposable
database; an import runs against a live one. This guide covers the decisions
that only matter in the second case. For how to build the rows themselves,
see [Building Rows](building_rows.html).

## The entry point

For a single table, skip the seeder machinery — call `copy_to_table/4`
directly:

```elixir
"upload.csv"
|> Blink.from_csv(stream: true)
|> Blink.copy_to_table("readings", MyApp.Repo, timeout: :timer.minutes(1))
```

CSV values arrive as strings, and that is fine: `COPY` parses text input into
the column's type, so `"123"` inserts into an `integer` column and
`"2026-08-07 12:00:00"` into a `timestamp` without any transformation.

## Imports that span tables

The seeder pipeline is not seeding-specific either, and once an import
writes more than one table it starts to earn its keep: tables are copied in
declaration order (parents before children), `table/2` clauses read earlier
tables and context off the seeder, and the default atomic run wraps every
table in one transaction. `use Blink` works in an import module exactly as
it does in a seeder module:

```elixir
defmodule MyApp.ReadingsImport do
  use Blink

  def call(path) do
    batch_id = Ecto.UUID.generate()

    new()
    |> put_context(path: path, batch_id: batch_id)
    |> put_table("import_batches", [%{id: batch_id, source: path}])
    |> with_table("readings")
    |> run(MyApp.Repo, timeout: :timer.minutes(1))
  end

  @impl true
  def table(seeder, "readings") do
    from_csv(seeder.context.path,
      stream: true,
      transform: &Map.put(&1, "batch_id", seeder.context.batch_id)
    )
  end
end
```

The two forms mix by design: the batch row is data in hand at the call site,
so `put_table/3` takes it directly, while the readings derive from context,
so they come from a `table/2` clause. Declaring `import_batches` first
satisfies the foreign key on `readings.batch_id`, and tagging every reading
with the batch id is the delete-by-batch-id handle the next section calls
for. The batch id is a `uuid`, so assigning it client-side leaves no
sequence behind to desynchronize (see Sequences below).

## Choosing an atomicity posture

The `:atomic` default is tuned for seeding, and on a live table the trade-off
reads differently:

  * **`atomic: true` (the default)** is all-or-nothing — but it holds one
    connection and one transaction for the entire import. For a large import
    that is a long-running transaction on a production database: locks are
    held longer, and vacuum cannot clean up row versions created while it
    runs. Right for correctness-critical imports of moderate size.

  * **`atomic: false`** commits batches independently over parallel
    connections — the production-friendly mode for very large imports. The
    cost: a failure partway leaves earlier batches committed, so the import
    must be re-runnable. Give rows an import batch id you can delete by (as
    `ReadingsImport` above does), or import into a staging table (below).

An import that *replaces* a table wholesale can pass `truncate: true`
instead of deleting by hand: with `atomic: true` the truncate and the copy
commit as one transaction, so readers see the old contents until the swap
completes — at the price of the truncate's `ACCESS EXCLUSIVE` lock blocking
every reader and writer for the import's duration. Not an upsert: rows not
in the input are gone.

A note on transactions of your own: an import running inside your
`Repo.transaction` must stay atomic — `atomic: false` copies over separate
connections that cannot see the transaction's uncommitted data and whose
commits survive its rollback. See `Blink.Seeder.run/3` for the full contract.

## Upserts: the staging-table pattern

`COPY` has no `ON CONFLICT`. To upsert into a live table, copy fast into a
staging table, then merge in SQL:

```elixir
Repo.query!("CREATE UNLOGGED TABLE IF NOT EXISTS readings_staging (LIKE readings)")
Repo.query!("TRUNCATE readings_staging")

:ok = Blink.copy_to_table(rows, "readings_staging", Repo, atomic: false)

Repo.query!("""
INSERT INTO readings SELECT * FROM readings_staging
ON CONFLICT (device_id, taken_at) DO UPDATE SET value = EXCLUDED.value
""")
```

This keeps the fast path fast (an unlogged table skips WAL, and a partial
copy into staging is harmless) while the merge into the live table is a
single atomic statement. Use a real or `UNLOGGED` staging table, not a
`TEMPORARY` one: with `atomic: false` the batches arrive over multiple
connections, and a temporary table is only visible to the connection that
created it.

## Rows from external sources

Every row must have the same keys as the first row — a mismatch raises
`Blink.RowError`. External data with optional fields must be normalized
before copying, choosing explicitly which columns every row provides:

```elixir
defaults = %{device_id: nil, taken_at: nil, value: nil, note: nil}
rows = Enum.map(raw_rows, &Map.merge(defaults, &1))
```

This is not busywork: without it, which columns the import sends would depend
on which row happened to come first.

## Sequences

Do **not** use `reset_sequences: true` on a table receiving concurrent
inserts. The reset derives its target from the `MAX()` of rows visible to its
snapshot, so it can move the sequence backwards past values already handed
out to in-flight transactions — causing unique violations later, far from the
import. For live tables, either omit the id key entirely and let the sequence
assign ids as the rows arrive, or use identifiers from the source system that
cannot collide with the sequence range (`uuid`, or ids outside it).

## Connections, pools, and where imports run

With `atomic: false`, each of the `:concurrency` workers (default: 6) checks
out its own connection — size the repo's `pool_size` so the import cannot
starve the application's queries, or point Blink at a dedicated repo for
imports. With `atomic: true` a single connection is held for the whole
import.

Either way, a large import does not belong in a web request: it holds
connections for longer than a request should live. Run it in a background
job and let the job's retry policy pair with your atomicity choice —
all-or-nothing imports retry wholesale; batch-committed imports need the
delete-by-batch-id or staging cleanup above.

The per-operation `:timeout` (default: 15 seconds) bounds each batch's
database work; size it to your batch size and network rather than disabling
it — a wedged import should fail, not hold its connections forever.

## Observing imports

Each `copy_to_table/4` call emits `[:blink, :copy, :start]`, then
`[:blink, :copy, :stop]` (with a `:row_count` measurement) on success or
`[:blink, :copy, :exception]` on failure. The run and build events
documented in `Blink.Telemetry` belong to the seeder pipeline —
`ReadingsImport` above emits them, but a direct `copy_to_table/4` call does
not — so for direct copies attach your own handler:

```elixir
:telemetry.attach(
  "import-logger",
  [:blink, :copy, :stop],
  fn _event, measurements, metadata, _config ->
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("Imported #{measurements.row_count} rows into #{metadata.table_name} in #{ms} ms")
  end,
  nil
)
```

## Triggers and constraints

`COPY` fires row-level triggers and checks constraints per row, exactly like
ordinary inserts — on a live table that means production side effects
(audit rows, notifications, denormalization) run for every imported row.
If a trigger is expensive, the staging-table pattern above confines the
per-row work to the final `INSERT ... SELECT`, where you control it.
