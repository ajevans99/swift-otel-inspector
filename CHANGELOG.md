# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/) and
this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-07-20

### Added

- `InspectorTelemetry`, a small composition root that retains one bounded trace,
  log, and metric store set and creates lifecycle-scoped
  `InspectorExporterSet` values.
- A DEBUG-only consumer recipe for adapting the active runtime's exporters to
  `TelemetryObserverExporters`, presenting tabbed SwiftUI
  diagnostics, and preserving runtime-owned flush and shutdown behavior.

## [0.2.0] - 2026-07-16

### Added

- Bounded log and metric stores with redaction, cardinality controls, and
  deterministic eviction.
- OpenTelemetry Swift log and metric exporters.
- Searchable, severity-aware structured log inspection and correlated trace
  timelines.
- Swift Charts metric inspection for gauges, counter rates, sums, summaries,
  and explicit or exponential histograms.
- Correlated OTLP JSON fixtures for logs and metrics.
- Native iOS example app demonstrating traces, logs, and live metrics.

### Changed

- Hardened exporter lifecycle handling and metric identity, sizing, and
  presentation.
- Replaced the standalone example package with an Xcode project in the shared
  workspace.

## [0.1.0] - 2026-07-15

### Added

- Bounded, actor-owned completed-span storage with redaction and age eviction.
- OpenTelemetry Swift span exporter integration.
- SwiftUI trace tree, waterfall, filtering, sorting, and span details.
- Standalone iOS and macOS example consumer.
- OTLP JSON trace fixture and deterministic package tests.
