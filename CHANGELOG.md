# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-21

### Added
- **Reader** — read CSV, TSV, JSON and Excel (`.xlsx`) files into a unified `Dataset`.
- **Cleaner** — trim whitespace, remove duplicates, handle missing values
  (drop / fill / interpolate), coerce types, and normalize dates, emails and phones.
- **Validator** — declarative rule DSL (`required`, `type`, `range`, `format`,
  `inclusion`, `length`, cross-field `cross`) returning a detailed error report
  with row/column references.
- **Transformer** — filter, sort, group, aggregate (sum/avg/count/min/max),
  pivot tables and dataset merges (inner/left/right/outer joins).
- **Reporter** — export to CSV, JSON, and formatted terminal tables.
- **API** — fetch JSON from any REST endpoint and merge it with local data.
- **CLI** — `datacruncher process` with cleaning, transform, validation and
  reporting flags.
- RSpec test suite covering every module, and a GitHub Actions CI workflow.

[Unreleased]: https://github.com/sja-thedude/DataCruncher/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sja-thedude/DataCruncher/releases/tag/v0.1.0
