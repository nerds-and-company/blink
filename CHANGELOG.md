# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[0.4.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.4.0
