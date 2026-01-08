# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `Blink.from_csv/2` function for reading CSV files into maps
- Support for CSV files with headers (inferred from first row by default)
- Support for CSV files without headers via `:headers` option
- `:transform` option for CSV type conversion and data transformation
- `Blink.from_json/2` function for reading JSON files into maps
- Support for JSON arrays of objects with automatic type preservation
- `:transform` option for JSON data transformation

## [0.1.1] - 2026-01-08

### Changed
- Lowered Elixir requirement from 1.18 to 1.14 for better compatibility
- Improved package description and documentation

## [0.1.0] - 2026-01-08

### Added
- Initial release of Blink
- Fast bulk data insertion using PostgreSQL's COPY command
- DSL for defining seeders with `use Blink`
- Support for multiple tables with insertion order
- Context sharing between table definitions
- Configurable batch size for large datasets
- Transaction support with automatic rollback on errors
- Comprehensive test suite with integration tests
- Full documentation and examples

[0.1.0]: https://github.com/nerds-and-company/blink/releases/tag/v0.1.0
