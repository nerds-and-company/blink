# Changelog

## [Unreleased]

### Fixed
- Fixed CSV escaping in PostgreSQL COPY adapter: strings containing special characters (pipe `|`, double quotes `"`, newlines, carriage returns, backslashes) are now properly escaped to prevent data corruption

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

[0.4.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.4.1
[0.4.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.4.0
