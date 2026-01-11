# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New guide: "Custom Adapters" - documentation for creating custom database adapters
- Added public `Blink.Store.key()` type for table and context keys
- Added public `is_key/1` guard for validating table and context keys
- Added error handling in `Blink.Adapter.Postgres` to return `{:error, Exception.t()}` on database failures
- Added GitHub Actions CI workflow with test, format, and Dialyzer jobs
- Added support for `batch_size: :infinity` option in `copy_to_table/4` to disable CSV batching

### Changed
- **BREAKING**: Changed return type of `insert/2` and `insert/3` from `:ok | {:error, any()}` to `{:ok, any()} | {:error, any()}`.
- **BREAKING**: Moved `copy_to_table/4` from the `__using__` macro to a public module function.
- **BREAKING**: `copy_to_table/4` now raises `ArgumentError` when the adapter module doesn't define `call/4`.
- Refactored copy implementation into adapter pattern with `Blink.Adapter.Postgres` module for better code organization and to support future database adapters (e.g., MySQL)
- Added `:adapter` option to `copy_to_table/4` to allow specifying a custom adapter module. Defaults to `Blink.Adapter.Postgres`.
- Refactored store manipulation logic from `__using__` macro into `Blink.Store` module for better code organization
- Replaced `binary() | atom()` type annotations with `Blink.Store.key()` throughout the codebase for consistency
- Increased Elixir requirement from 1.14 to 1.15 for compatibility with NimbleCSV
- Updated type specifications in `Blink.Adapter.Postgres` to use `{:error, Exception.t()}` instead of `{:error, any()}` for better type safety

### Fixed
- Fixed Dialyzer warnings in `Blink.Adapter.Postgres` by adding proper error handling and updating type specifications

## [0.2.0] - 2026-01-09

### Added
- `Blink.from_csv/2` function for reading CSV files into maps
- Support for CSV files with headers (inferred from first row by default)
- Support for CSV files without headers via `:headers` option
- `:transform` option for CSV type conversion and data transformation
- `Blink.from_json/2` function for reading JSON files into maps
- Support for JSON arrays of objects with automatic type preservation
- `:transform` option for JSON data transformation
- New guide: "Loading Data from Files"
- New guide: "Using Context"
- New guide: "Integrating with ExMachina"

### Changed
- Simplified "Getting Started" guide to focus on core concepts
- Refactored CSV and JSON functionality into dedicated internal modules

## [0.1.1] - 2026-01-08

### Changed
- Lowered Elixir requirement from 1.18 to 1.14 for better compatibility
- Improved package description and documentation

## [0.1.0] - 2026-01-08

### Added
- Initial release of Blink
- Fast bulk data insertion using PostgreSQL's COPY command
- Callback-based pattern for defining seeders with `use Blink`
- Support for multiple tables with insertion order
- Context sharing between table definitions
- Configurable batch size for large datasets
- Transaction support with automatic rollback on errors
- Comprehensive test suite with integration tests
- Full documentation and examples

[0.2.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.2.0
[0.1.1]: https://github.com/nerds-and-company/blink/releases/tag/v0.1.1
[0.1.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.1.0
