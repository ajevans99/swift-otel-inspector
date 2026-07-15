# SwiftOTelInspector

An embeddable, on-device OpenTelemetry inspector for Swift applications.

SwiftOTelInspector aims to give Swift developers a fast local feedback loop for
understanding traces, logs, and metrics without first deploying an OpenTelemetry
Collector or a remote observability backend.

```text
Application instrumentation
  -> OpenTelemetry Swift
     |-> OTLP exporter -> Grafana, Jaeger, or another backend
     `-> SwiftOTelInspector -> local on-device viewer
```

## Motivation

Most Swift OpenTelemetry examples end with "export the data to a collector."
That is appropriate for production, but it creates a large setup barrier for
developers learning instrumentation or debugging an application locally.

SwiftOTelInspector should make the shortest learning loop possible:

```text
Create a span -> run the app -> inspect the trace tree
```

The package is intended for:

- Learning OpenTelemetry concepts such as context propagation, parentage, span
  lifetime, attributes, events, status, sampling, and asynchronous boundaries.
- Debugging iOS, macOS, watchOS, and visionOS applications on the device where
  telemetry originates.
- Adding a developer diagnostics screen to an application.
- Inspecting local telemetry while optionally exporting the same signals to a
  production backend.
- Building domain-specific inspectors on top of standard OpenTelemetry signals.

It is a developer diagnostic tool, not a production telemetry backend.

## Package structure

```text
SwiftOTelInspector
|-- InspectorCore
|   |-- bounded signal store
|   |-- trace, log, and metric models
|   |-- filtering and querying
|   `-- privacy and redaction hooks
|-- InspectorOpenTelemetry
|   |-- span processor and exporter
|   |-- log exporter
|   `-- metric reader and exporter
`-- InspectorSwiftUI
    |-- live timeline
    |-- trace tree
    |-- structured logs
    `-- metric charts
```

The core and OpenTelemetry integration should not depend on SwiftUI. This keeps
the storage and exporter useful to server-side Swift, command-line tools, tests,
and applications that provide their own interface.

The package should consume standard OpenTelemetry Swift protocols. Integrations
with libraries such as `swift-composable-otel` should remain small, optional
adapters rather than requirements.

`InspectorCore` should own immutable telemetry snapshots rather than expose
OpenTelemetry SDK types. `InspectorOpenTelemetry` is responsible for converting
completed SDK spans into those snapshots. This keeps storage and presentation
stable when the upstream SDK changes.

## Requirements

- Swift 6.0 or newer.
- iOS 17 or newer.
- macOS 13 or newer.
- OpenTelemetry Swift Core 2.5.1.

SwiftOTelInspector follows Semantic Versioning. `VERSION` and
`InspectorCore.version` identify the planned release, and a `v<version>` tag
publishes a GitHub release only after version validation, tests, a release
build, and the external consumer check pass.

## Installation

Add this repository as a Swift Package dependency, then select only the products
the application needs:

- `InspectorCore` provides immutable telemetry models and the bounded store.
- `InspectorOpenTelemetry` converts completed OpenTelemetry SDK spans.
- `InspectorSwiftUI` provides the trace browser.

Applications using the exporter also need the `OpenTelemetrySdk` product from
[`opentelemetry-swift-core`](https://github.com/open-telemetry/opentelemetry-swift-core).

## Quick start

```swift
import InspectorCore
import InspectorOpenTelemetry
import InspectorSwiftUI
import OpenTelemetrySdk
import SwiftUI

let store = TraceStore(
    configuration: TraceStoreConfiguration(
        maximumSpanCount: 1_000,
        maximumEstimatedBytes: 5_000_000,
        maximumAge: .seconds(3_600),
        maximumAttributeValueBytes: 4_096
    ),
    redactor: { key, value in
        key == "user.email" ? nil : value
    }
)

let inspectorExporter = InspectorSpanExporter(store: store)
let processor = BatchSpanProcessor(spanExporter: inspectorExporter)
let tracerProvider = TracerProviderSdk(spanProcessors: [processor])
```

Embed the viewer wherever developer diagnostics belong:

```swift
TraceInspectorView(store: store)
```

Open the standalone example package in Xcode:

```sh
open Examples/InspectorExample/Package.swift
```

Select the `InspectorExampleApp` scheme and run it on an iOS 17 simulator or
macOS. The example is a separate package consumer and sends completed spans to
both the local inspector and the OpenTelemetry stdout exporter.

### Compose with remote export

Use OpenTelemetry Swift's standard `MultiSpanExporter` when the application
should inspect and remotely export the same sampled spans:

```swift
let exporter = MultiSpanExporter(
    spanExporters: [inspectorExporter, remoteExporter]
)
let processor = BatchSpanProcessor(spanExporter: exporter)
```

Every child exporter is invoked. The combined result is a failure if any child
fails. Applications that require independent failure and lifecycle handling can
register separate span processors instead.

### Privacy and limits

Redaction runs before snapshots enter the store. Returning `nil` from the
redactor removes an attribute. Remaining string and byte values are truncated
to `maximumAttributeValueBytes`; count, estimated-byte, and age limits then
enforce deterministic eviction. Applications remain responsible for deciding
which domain-specific attributes are safe to retain.

## Development fixtures

[`fixtures/otlp/sync-trace.json`](fixtures/otlp/sync-trace.json) is a small
OTLP/HTTP JSON trace for parser development, UI previews, and deterministic
tests. It models a failed synchronization request across an iOS application and
an API service, including cross-resource parentage, semantic convention
attributes, mixed attribute value types, a retry, exception events, a span link,
and error status propagation.

The fixture is an OTLP export request body and can be submitted directly to a
generic OTLP/HTTP receiver, such as a local OpenTelemetry Collector. The
inspector does not provide an OTLP receiver:

```sh
curl \
  -H 'Content-Type: application/json' \
  --data-binary @fixtures/otlp/sync-trace.json \
  http://localhost:4318/v1/traces
```

## Version 0.1: traces

The first release stays deliberately narrow and inspects completed
spans only. Live or active-span inspection requires lifecycle observation beyond
the exporter contract and is deferred until after the completed-span experience
is reliable.

1. Implement an in-memory span exporter.
2. Convert completed spans into immutable, inspector-owned snapshots.
3. Store snapshots with configurable count, byte, and age limits.
4. Truncate oversized attribute values before storage.
5. Group spans by trace ID.
6. Render a list of traces.
7. Render expandable parent-child span trees, including orphan spans.
8. Render a relative-time waterfall for latency analysis.
9. Show span name, duration, status, service, attributes, events, and timestamps.
10. Filter and sort traces by name, service, status, attributes, time, and duration.
11. Compose with a remote exporter without changing its sampling, flush,
    shutdown, or error behavior.
12. Provide deterministic tests for ordering, parentage, malformed data,
    eviction, concurrent export, flush, and shutdown.

This is enough to make the package useful while teaching the most important
OpenTelemetry concepts.

The package declares only platforms exercised in CI. Additional Apple platforms
and Linux support can be added when they have build and test coverage.

## Future roadmap

- Correlated structured logs using trace and span context.
- Counters, gauges, and histogram summaries.
- A unified live timeline across traces, logs, and metrics.
- Small Swift Charts visualizations for metric history.
- JSON and OTLP diagnostic bundle export.
- Attribute allowlists and configurable redaction.
- Optional encrypted local persistence.
- Custom attribute renderers for domain-specific diagnostics.
- iPhone, iPad, macOS, watchOS, and visionOS interfaces appropriate to each
  screen size.
- Sample applications demonstrating async work, failures, retries, and context
  propagation.

## Design principles

### Use OpenTelemetry standards

Applications should not need proprietary instrumentation to use the inspector.
The package should observe signals through standard OpenTelemetry Swift extension
points wherever possible.

### Keep exporters off the main actor

Signal ingestion, redaction, accounting, and storage must remain concurrency-safe
and must not require the main actor. Export callbacks should copy or enqueue
bounded work promptly rather than block application work. Only presentation
belongs on the UI actor.

### Bound resource use

On-device telemetry must not grow without limit. The store should enforce:

- Maximum signal count.
- Maximum estimated bytes.
- Maximum signal age.
- Maximum attribute value size.
- Deterministic eviction.

Malformed completed spans should remain inspectable when safe, including as
orphans, but must obey the same limits as valid spans.

### Redact before storage

Sensitive attributes should be rejected or transformed before entering the local
store. Hiding values only in the UI still leaves private data resident in memory
or diagnostic exports.

Version 0.1 truncates all attribute values to a configurable maximum and
provides a redaction hook that runs before snapshots enter the store. Applications
remain responsible for choosing which domain-specific attributes are safe.

### Make the viewer optional

Projects should be able to depend on the exporter and store without shipping the
SwiftUI interface. Production builds should be able to omit or disable the
inspector entirely.

### Compose with remote export

Local inspection and remote observability should work together:

```text
OpenTelemetry signal
  |-> bounded local inspector
  `-> sampled OTLP exporter
```

Using the inspector must not change application behavior or prevent normal
export to Grafana, Jaeger, Tempo, or another OTel-compatible system.

The inspector composes through standard OpenTelemetry processor and exporter
mechanisms. `MultiSpanExporter` invokes every child and merges their results, so
a failure from any local or remote child makes the combined result a failure.
Separate processors provide independent failure and lifecycle handling.

## Example use case: cross-device synchronization

A synchronization engine could expose short local phases as spans:

```text
sync.flush
|-- persistence.load_outbox
|-- transport.queue_transfer
|-- transport.accelerate
`-- persistence.mark_attempt
```

Metrics could summarize queue depth, acknowledgement latency, retry counts, and
recovery frequency. Structured logs could record bounded state transitions such
as peer authentication, gap detection, or full-resync requests.

For completed operations, the on-device inspector would answer:

> Where did this operation spend time, and what happened on this device?

Remote aggregate telemetry would answer:

> Is synchronization healthy across the release population?

The package should enable both stories without learning anything about workout
content, application domain identifiers, or other private payloads.

## Non-goals

- Replacing Grafana, Jaeger, Tempo, Loki, or an OpenTelemetry Collector.
- Providing durable, unbounded production telemetry storage.
- Automatically collecting arbitrary application state.
- Defining a proprietary telemetry protocol.
- Making privacy or consent decisions on behalf of the host application.

## Status

Version 0.1 is prepared as a release candidate. The package includes immutable
trace snapshots, a bounded actor-owned store with scheduled expiration, an
OpenTelemetry Swift span exporter, a fixture-backed SwiftUI tree and waterfall,
rich filtering, tests, and a standalone example application. Logs, metrics,
persistence, and active-span inspection remain future work.
