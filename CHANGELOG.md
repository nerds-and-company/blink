# Changelog

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

[0.6.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.6.1
[0.6.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.6.0
[0.5.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.5.1
[0.5.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.5.0
[0.4.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.4.1
[0.4.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.4.0
