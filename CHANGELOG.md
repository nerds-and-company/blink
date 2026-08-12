# Changelog

## [Unreleased]

### Added
- `[:blink, :copy, :exception]`, emitted when a table's copy — or its sequence reset, with `reset_sequences: true` — fails, completing the per-table copy events. A failed copy previously emitted only `:start`: inside `Blink.Seeder.run/3` the failure surfaced through the run span, but a direct `copy_to_table/4` call (which emits no run events) failed with no event at all, leaving the raised exception as the only signal. Measurements: `:duration`; metadata: the `:start` metadata plus `:kind`, `:reason`, and `:stacktrace`. `Blink.Telemetry.attach_default_logger/1` attaches it and logs copy failures at `:error`, naming the failed table — inside a seeder run alongside the run span's error line, which names the seed.

### Documentation
- Every complete seeder module in the README, the guides, and the `Blink` moduledoc now carries `@impl true` on its first `table/2` clause; only the Building Rows guide did before. The examples implemented a behaviour callback without annotating it, so a reader copying one into a project starts from code Elixir will not check against `Blink`: misspell or mis-arity a `table/2` clause later and it silently becomes an ordinary private-looking function instead of a compile-time warning. Partial snippets that show a clause without its surrounding `defmodule` are left alone, since `@impl` reads as noise outside a module.
- The Bulk Imports guide now shows the seeder pipeline as an import entry point alongside the direct `copy_to_table/4` call: a `use Blink` import module mixing a hand-assigned `import_batches` row (`put_table/3`) with CSV-derived readings (`with_table/2` + `from_csv/2`), which makes the guide's own delete-by-batch-id advice concrete. The guide previously told every reader to skip the seeder machinery — right for a single table, but it left multi-table imports, where declaration order, cross-table references, and the single-transaction run apply just as well, reimplementing `run/3` by hand.
- Two honesty fixes in the Building Rows guide's canonical conventions: the string-table-keys bullet now acknowledges that atoms work identically (the choice is a preference, and the API reference always said both work), and the one-timestamp bullet warns to use distinct stamps when the application orders or paginates by `inserted_at` without a tiebreaker — rows tied on a single timestamp paginate nondeterministically.
- Refined the Building Rows guide's data-placement convention: row data lives in the `table/2` clause that uses it, and moves to a module attribute only when it is shared across clauses, derived at compile time, or large enough to bury the clause's logic. The guide previously prescribed module attributes unconditionally, which hoisted single-use lists away from their point of use; the canonical example now keeps its data in the clauses.

## [0.9.1] - 2026-08-07

### Fixed
- With `reset_sequences: true`, the sequence reset now runs before the copy `:stop` event, so a failing reset (for example, a role without `UPDATE` privilege on the sequence) can no longer raise after a success-signaling `:stop` was emitted. The reset's time is included in the event's `:duration`.
- `Blink.Telemetry.attach_default_logger/1` now attaches `[:blink, :build, :exception]`, so a table or context builder that raises is logged with its duration; the event was emitted but never attached, leaving build failures unlogged. Run and build failures are always logged at `:error` — the `level` argument applies to the run start and stop lines, which is what the code always did; the documentation previously claimed the level applied to failures too.

### Documentation
- Corrected the README feature bullets added in 0.9.0: copy instrumentation is a pair of plain events (`:start`, and `:stop` with a `:row_count`) rather than a span — there is no copy exception event, and a failed copy emits no `:stop`, which `Blink.Telemetry` now states explicitly — and sequence resets are opt-in via `reset_sequences: true`, not automatic.
- Added `:reset_sequences` to the Configuring Options guide (global and per-table) and to the `copy_to_table/4` docs; both still enumerated the pre-0.9.0 option set.
- Documented in Loading Data from Files that every row must share the first row's keys (`Blink.RowError`) and how to normalize JSON objects with optional fields. The file-loading guide is the primary path for sparse input, but the normalization recipe lived only in the Bulk Imports guide and the `Blink.RowError` docs.

## [0.9.0] - 2026-08-07

### Added
- `Blink.RowError`, raised when a row's keys differ from the first row's. The message names the table, the offending row's index, and the missing and extra keys.
- Telemetry spans for the whole pipeline: `[:blink, :build, :start/:stop/:exception]` around each table or context builder (builders run at declaration time, so their cost — usually the bulk of a seed's wall time — was invisible to the copy events), `[:blink, :run, :start/:stop/:exception]` around `Blink.Seeder.run/3`, and a `[:blink, :copy, :stop]` event with a `:row_count` measurement completing the existing `:start`. See `Blink.Telemetry` for the full event reference.
- `Blink.Telemetry.attach_default_logger/1` (and `detach_default_logger/0`), which logs run start, stop, and failure at a configurable level and per-declaration build and per-table copy timings at `:debug` — replacing the hand-rolled `:timer.tc` + `Logger.info` wrappers around seed scripts.
- A `:reset_sequences` option (default: `false`) on `Blink.Seeder.run/3`, `Blink.copy_to_table/4`, and `Blink.Adapter.Postgres`, also settable per-table. After a table's copy it advances the sequence behind each `serial` or identity primary key column past the highest copied value, so the application's next ordinary insert no longer collides with a seeded row. Primary keys without a sequence (`uuid`, self-managed integers) are skipped. This replaces the `setval` query the Getting Started guide told you to run by hand. Intended for seed-time use: on a table receiving concurrent inserts, the reset can move the sequence backwards past values already handed out to in-flight transactions.
- `with_table/2,3` (defined by `use Blink`) accepts a list of table names, declaring each in order as if by one call per name, with the options applying to every table in the list: `new() |> with_table(["users", "posts", "comments"])`.
- `Blink.fetch_row!/3` (imported by `use Blink`), which fetches the first row of a declared table matching the given field values and raises a descriptive `ArgumentError` on a miss — replacing hand-rolled `Enum.find/2` lookups whose `nil` result surfaces later as a crash far from the cause. Atom and string table names are interchangeable, matching the rest of the seeder API. Use it with list-backed tables only; the lookup enumerates the table, so it would consume a single-use stream.

### Changed
- Added an explicit `telemetry ~> 1.1` requirement. Blink has emitted telemetry events for several releases but depended on `telemetry` only transitively through Ecto, leaving the real requirement unstated; the new spans rely on `:telemetry.span/3` and the test suite on `:telemetry_test` (telemetry 1.1+), so it is now declared.
- **Breaking:** Every row must now have the same keys as the first row, or the copy raises `Blink.RowError`. The column list is read from the keys of the first row, so previously a key missing from a later row was silently inserted as `NULL` (or failed the COPY on a `NOT NULL` column without naming the culprit) and an extra key was silently dropped — the documented "all maps must have the same keys" contract was never enforced. Validation runs as rows are consumed: with `atomic: true` (the default) a failed seed leaves nothing behind; with `atomic: false` a mismatch surfaces like any other mid-copy failure, with earlier batches possibly committed. Rows from sparse sources (optional JSON fields and the like) that relied on missing keys becoming `NULL` must now be normalized first, e.g. `Map.merge(defaults, row)` — which also frees the result from depending on which row happened to come first.

### Documentation
- Added the [Building Rows](guides/building_rows.md) guide: build plain maps, not schema structs. It explains the three `Repo.insert` habits that do not carry over to COPY (column selection, autogeneration, nil handling), shows a canonical seeder shape (fixed rows in module attributes, a `call/0` entrypoint, string table names, one timestamp for the whole seed), and covers passing calendar structs directly, leaving columns to their database defaults, entrypoint naming (`run/2,3` on your module overrides Blink's — the documented mechanism, whether you meant it or not), scoping the dependency per mix env, CI timeouts, testing seeders under `Ecto.Adapters.SQL.Sandbox` (atomic seeds enroll in the sandbox, so `async: true` works), and trigger behavior during COPY.
- Rewrote the ExMachina guide around the two real pairings: map factories dedicated to seeding (the simple path — the maps are the rows), and struct factories shared with the test suite, which should stay structs and be converted at the seeder boundary. The guide now gives the conversion recipe — `to_row/2` (`Map.from_struct/1` + `Map.take(__schema__(:fields))` with an explicit-vs-database id policy) and `drop_all_nil_columns/1` for schemas that lean on database defaults — instead of pretending the struct case does not exist.
- Added the [Bulk Imports Outside Seeding](guides/bulk_imports.md) guide. Blink's copy path is a general bulk-insert primitive, but every existing doc assumed an idle, disposable database; this guide covers what changes on a live one — the atomicity trade-off reread for production tables (a fully atomic import is one long transaction; `atomic: false` batch commits need a re-runnable design), the staging-table pattern for upserts (`COPY` has no `ON CONFLICT`; use a real or `UNLOGGED` staging table, since a `TEMPORARY` one is invisible to the parallel copy connections), normalizing rows from sparse external sources, why `reset_sequences` must not run against concurrent inserts, pool sizing so an import cannot starve the application, and observing imports through the copy telemetry events.

## [0.8.0] - 2026-08-05

### Added
- `Blink.MissingClauseError`, raised when a table or context is declared with no matching callback clause. The message names the key and shows the clause to add.
- Added an `:atomic` option (default: `true`) to `Blink.Seeder.run/3`, `Blink.copy_to_table/4`, and `Blink.Adapter.Postgres`. The whole seed (or copy) runs over a single database connection inside one transaction — any failure rolls everything back — while rows are encoded in parallel across cores (tunable via `:concurrency`). Input row order is always preserved. A failed seed leaves nothing behind, which makes re-running it after a fix safe. Pass `atomic: false` to copy batches over parallel connections instead, which measured 1.4× faster on 500k rows and 2.1× on 10k (local PostgreSQL) at the cost of independent per-batch commits.

### Changed
- **Breaking:** Redesigned the copy options around two orthogonal knobs: `:atomic` (all-or-nothing or not) and `:concurrency` (number of parallel workers — COPY connections when `atomic: false`, row encoders when `atomic: true`). `:max_concurrency` is renamed to `:concurrency`.
- **Breaking:** Atomicity is now controlled exclusively by `:atomic`, and seeds are atomic by default. `concurrency: 1` (previously `max_concurrency: 1`) no longer makes a seed atomic as a side effect, and `atomic: false` disables the surrounding transaction entirely so every batch commits independently. The old transaction was not protecting parallel seeds to begin with: each COPY ran on its own connection outside it, so at `max_concurrency > 1` (the default) a failure already left completed batches committed despite the apparent rollback — which is why the default is now `true` rather than preserving that behaviour. This also removes the `pool_size >= max_concurrency + 1` requirement; `pool_size >= concurrency` suffices, and an atomic seed needs only one connection.
- **Breaking:** Options are no longer silently ignored. Adapters own and validate their option vocabulary, so unknown keys and invalid values raise `ArgumentError` whether they enter through `run/3`, `copy_to_table/4`, or per-table options. The run-level options `:adapter`, `:atomic`, and `:timeout` raise `ArgumentError` when passed per-table via `with_table/3,4` or `put_table/4`, because a per-table override could silently void a run-level guarantee such as atomicity.
- **Breaking:** `:timeout` now has one meaning — the time allowed for each database operation — and one default (15,000 ms) everywhere, including direct `copy_to_table/4` calls (previously `:infinity`). With `atomic: false` it bounds each batch's COPY transaction; with `atomic: true` it is enforced server-side via `SET LOCAL statement_timeout`, since a checkout deadline cannot bound individual operations inside one transaction. Row encoding is no longer subject to it.
- **Breaking:** `[:blink, :copy, :start]` telemetry metadata now reports `:concurrency` and `:atomic` instead of `:max_concurrency`.
- **Breaking:** `from_csv/2` and `from_json/2` raise `ArgumentError` on unknown options, matching the copy options. Previously an unknown key was silently ignored — a typo'd `:stream` loaded the whole file into memory without complaint. `from_json/2` also validates `:transform` before reading the file.
- Encoding now memoizes the JSON encoding of repeated map (JSONB) values within a batch. Seeds that reuse the same JSONB value across many rows encode dramatically faster (14–127× on the encode step in benchmarks); unique-per-row maps are unaffected (large maps) or ~9% slower (small maps).
- Lowered the `ecto_sql` requirement from `~> 3.13` to `~> 3.10`, so Blink no longer forces applications onto Ecto 3.13. `Blink.Seeder.run/3` now calls `Ecto.Repo.transaction/2` instead of `Ecto.Repo.transact/2`, which was the only Ecto 3.13 API in the library. Behaviour is unchanged: `run/3` discards the transaction body's return value and still returns `:ok`, and a failed copy still rolls the transaction back by raising.
- Added an explicit `ecto ~> 3.10` requirement. Blink calls `Ecto.Repo` callbacks directly, but previously depended on `ecto` only through `ecto_sql`, which left the real floor unstated — and unpinnable, since a loose `ecto_sql` requirement permits far newer Ecto versions. CI now resolves both packages at their exact minimum (3.10.3 / 3.10.2) and runs the suite against them, so the declared floor is tested rather than asserted.
- A `with_table/2` or `with_context/2` call whose callback clause is missing now raises `Blink.MissingClauseError` instead of a bare `FunctionClauseError`. Previously only the degenerate case — a module defining no `table/2` or `context/2` clauses at all — produced a helpful error, because a user-defined clause replaces the fallback injected by `use Blink`.
- The missing-clause fallback injected by `use Blink` raises `Blink.MissingClauseError` instead of `ArgumentError`. `Blink.MissingClauseError` is not an `ArgumentError`, so code that rescues `ArgumentError` around seeder construction to catch a missing clause must rescue `Blink.MissingClauseError` instead. Duplicate table names and keys still raise `ArgumentError`.

### Fixed
- An atomic copy no longer leaves Blink's `statement_timeout` applied to the rest of a caller's transaction: the previous value is captured before the COPY and restored with `SET LOCAL` afterwards. Previously, running `copy_to_table(..., atomic: true)` inside your own `Repo.transaction` left every later statement in that transaction bounded by Blink's `:timeout` (15 seconds by default).
- `Blink.copy_to_table/4` now accepts an atom table name, as its documentation always claimed; previously an atom crashed with a `FunctionClauseError` from the adapter. The name is normalized to a string before reaching the adapter, matching what `Blink.Seeder.run/3` does for table keys.
- A failed COPY on the parallel path now raises in the calling process with its original stacktrace. Previously the linked task's death took the caller down with an exit signal, so the documented exception could not be rescued and an insertion failure could go unhandled. Every COPY path also raises on an unexpected `{:error, _}` result from a batch; the sequential path previously swallowed it and kept copying.

### Documentation
- Documented the atomicity model in `Blink.Seeder.run/3` and rewrote the "Configuring Options" guide for the new options API.
- Documented the `:atomic` contract for custom adapters: `run/3` opens the transaction and relies on the adapter copying in the calling process, so an adapter that hands batches to other processes silently voids atomicity. Also corrected the Custom Adapters run-override example, which used `%Seeder{}` — `use Blink` imports `Blink.Seeder` rather than aliasing it, so that example did not compile.
- Documented that a seed running inside a transaction of your own must stay atomic: `atomic: false` copies over separate connections that cannot see the transaction's uncommitted data and whose commits survive its rollback.
- Documented that struct values (`DateTime`, `Date`, `Decimal`, ...) are JSON-encoded like any other map. Calendar structs work in `timestamp`, `date`, and `time` columns because PostgreSQL accepts the quoted result, but in a `text` column the stored value keeps the JSON quotes — pass `to_string(value)` for text columns.
- Recommended passing pre-encoded JSON strings for JSONB columns to avoid a `Jason.decode!`/`Jason.encode!` round trip.
- Documented that primary keys are chosen by you rather than generated by the database, so a table can reference IDs from an earlier table before anything is inserted. Every example already relied on this, but no guide stated it, leaving it to be inferred against the usual `c:Ecto.Repo.insert/2` flow where an ID only exists after insertion.
- Documented that explicit IDs do not advance a `serial`, `bigserial`, or identity sequence, and gave the `setval` query to run after seeding. Without it the seed succeeds and the application's next ordinary insert fails with a unique constraint violation.
- Raised the `ex_doc` requirement to `~> 0.40`, which generates an `llms.txt` and per-module Markdown alongside the HTML docs. `ex_doc` is a dev-only dependency, so this does not affect dependency resolution for applications using Blink.
- Documented the functions `use Blink` defines on your module — `with_table/2,3` and `with_context/2` — in the `Blink` moduledoc. They are defined on the calling module, so ExDoc never listed them, leaving `Blink.Seeder.with_table/4` as the only `with_table` in the API reference.
- Added guidance on choosing between the callback-based `with_*` functions and the direct `put_*` helpers, and marked `Blink.Seeder.with_table/4` and `Blink.Seeder.with_context/3` as the low-level forms.
- Corrected references to `with_table/4` in the Configuring Options and Providing Data Directly guides; the function that takes per-table options on a module using `use Blink` is `with_table/3`.
- Updated the Getting Started installation pin to `~> 0.7.0`; it still pointed at the 0.6.x series after v0.7.0 shipped.
- Updated the README installation pin to `~> 0.7.0`; it still pointed at the 0.6.x series after v0.7.0 shipped.
- Corrected the README requirements from "Ecto 3.0+" to "Ecto 3.10+"; the `~> 3.0` era ended in v0.6.3 but the README was never updated.
- Documented that `from_csv/2`'s explicit `:headers` option is for files without a header row, and that it does not skip the first row of a file that has one. The doc example previously showed explicit headers on the same headered file used by the other examples, which would return the header row as a data map.

## [0.7.0] - 2026-07-03

### Added
- `Blink.Adapter.Postgres` now encodes Elixir lists as PostgreSQL array literals (`{...}`), so `int[]`, `text[]`, `jsonb[]` and nested-array columns can be seeded by passing plain lists. A JSONB column holding a top-level JSON array should still be passed as a pre-encoded JSON string.

### Changed
- Lists are now encoded as array literals instead of falling through to `to_string/1`. Most lists previously corrupted the value or raised, but a charlist happened to coerce to text — so a charlist value for a `text` column now produces an array literal. Pass a binary string for text columns.

## [0.6.3] - 2026-07-02

### Fixed
- Tightened the `ecto_sql` requirement from `~> 3.0` to `~> 3.13`. `Blink.Seeder.run/3` calls `Ecto.Repo.transact/2`, which was added in Ecto 3.13.0. Under the previous constraint the dependency resolved happily against Ecto 3.12, then raised `UndefinedFunctionError` at seed time; the requirement now fails at dependency resolution instead.

## [0.6.2] - 2026-07-01

### Added
- `Blink.put_context/2,3` and `Blink.put_table/2,3,4` for building a seeder directly from data that is already available, without a `context/2` or `table/2` callback. The `/2` forms take a keyword list to add several keys/tables at once (e.g. `put_context(user_id: id, project_indices: idx)`); `put_table/4` forwards per-table options (e.g. `:batch_size`, `:max_concurrency`). All are imported into modules that `use Blink`.
- Added the [Providing Data Directly](guides/providing_data_directly.md) guide.

## [0.6.1] - 2026-02-14

### Fixed
- Fixed `@spec` for `run/3` injected by `use Blink` returning `{:ok, any()} | {:error, any()}` instead of `:ok`

## [0.6.0] - 2026-02-01

### Added
- Added `:max_concurrency` option to `run/3` and `copy_to_table/4` for parallel COPY operations (default: 6).
- Added `:timeout` option to `copy_to_table/4` for batch operations (default: `:infinity`).
- Added per-table options support via `with_table/4`: `:batch_size` and `:max_concurrency` can now be set per table, overriding the global options passed to `run/3`.
- Added [Configuring Options](guides/configuring_options.md) guide.

### Changed
- Changed default `:batch_size` from 10,000 to 8,000 based on performance benchmarks.
- Batching now applies to both lists and streams (previously only streams were batched)

## [0.5.1] - 2026-01-21

### Changed
- Removed try-rescue block in `copy_to_table/4` for invalid adapters, allowing standard Elixir error handling

### Fixed
- Fixed stream being materialized twice when seeding from CSV files

## [0.5.0] - 2026-01-18

### Added
- Added `:timeout` option to `run/3` to configure transaction timeout
- Added `:batch_size` option to `run/3` to control stream chunking for backpressure (default: 10,000 rows per chunk). Only applies to streams; lists are sent as a single batch. This is different from the previously removed `batch_size` option which controlled CSV value batching.
- Added stream support: `table/2` callbacks can now return streams in addition to lists, enabling memory-efficient seeding of large datasets
- Added `:stream` option to `from_csv/2` to return a stream instead of a list for memory-efficient processing of large CSV files
- Added support for seeding JSONB columns: nested maps are automatically JSON-encoded during insertion

### Changed
- **Breaking:** Renamed `Blink.Store` to `Blink.Seeder`
- **Breaking:** Renamed `Blink.Seeder.insert/3` to `Blink.Seeder.run/3`
- **Breaking:** Renamed `add_table/2` to `with_table/2`
- **Breaking:** Renamed `add_context/2` to `with_context/2`
- **Breaking:** `run/3` now returns `:ok` on success and raises on failure (previously returned `{:ok, :inserted}` or `{:error, exception}`)
- **Breaking:** `copy_to_table/4` now returns `:ok` on success and raises on failure
- **Breaking:** Adapter `call/4` callback now returns `:ok` on success and raises on failure
- **Breaking:** Adapter `call/4` callback now receives `table_name` as a string (previously could be atom or string)

### Fixed
- Fixed CSV escaping in PostgreSQL COPY adapter: strings containing special characters (pipe `|`, double quotes `"`, newlines, carriage returns, backslashes) are now properly escaped to prevent data corruption

### Performance
- Optimized CSV encoding

## [0.4.1] - 2026-01-11

### Added
- `use Blink` now imports `new/0`, `from_csv/1`, `from_csv/2`, `from_json/1`, `from_json/2`, `copy_to_table/3`, and `copy_to_table/4` for convenience

### Changed
- Moved batch size documentation to its own guide
- Simplified the using_context guide

## [0.4.0] - 2026-01-11

### Added
- Initial release of Blink
- Fast bulk data insertion using PostgreSQL's COPY command
- Callback-based pattern for defining seeders with `use Blink`
- Support for multiple tables with deterministic insertion order to respect foreign key constraints
- Context sharing between table definitions
- Configurable batch size for large datasets (including `batch_size: :infinity` to disable batching)
- Transaction support with automatic rollback on errors
- `Blink.from_csv/2` function for reading CSV files into maps
- `Blink.from_json/2` function for reading JSON files into maps
- Adapter pattern with `Blink.Adapter.Postgres` for database-specific bulk insert implementations
- Comprehensive test suite with integration tests
- Full documentation and examples

[0.9.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.9.1
[0.9.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.9.0
[0.8.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.8.0
[0.7.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.7.0
[0.6.3]: https://github.com/nerds-and-company/blink/releases/tag/v0.6.3
[0.6.2]: https://github.com/nerds-and-company/blink/releases/tag/v0.6.2
[0.6.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.6.1
[0.6.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.6.0
[0.5.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.5.1
[0.5.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.5.0
[0.4.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.4.1
[0.4.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.4.0
