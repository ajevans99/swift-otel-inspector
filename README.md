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

## Proposed package structure

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

## Development fixtures

[`fixtures/otlp/sync-trace.json`](fixtures/otlp/sync-trace.json) is a small
OTLP/HTTP JSON trace for parser development, UI previews, and deterministic
tests. It models a failed synchronization request across an iOS application and
an API service, including cross-resource parentage, semantic convention
attributes, mixed attribute value types, a retry, exception events, a span link,
and error status propagation.

The fixture is an OTLP export request body and can be submitted directly to an
OTLP/HTTP traces endpoint:

```sh
curl \
  -H 'Content-Type: application/json' \
  --data-binary @fixtures/otlp/sync-trace.json \
  http://localhost:4318/v1/traces
```

## Version 0.1: traces

The first useful release should stay deliberately narrow:

1. Implement an in-memory span exporter.
2. Store a bounded number of completed spans.
3. Group spans by trace ID.
4. Render a list of traces.
5. Render expandable parent-child span trees.
6. Show span name, duration, status, service, attributes, events, and timestamps.
7. Filter traces and spans by name and status.
8. Provide deterministic tests for ordering, parentage, limits, and concurrent
   export.

This is enough to make the package useful while teaching the most important
OpenTelemetry concepts.

## Future roadmap

- Correlated structured logs using trace and span context.
- Counters, gauges, and histogram summaries.
- A unified live timeline across traces, logs, and metrics.
- Small Swift Charts visualizations for metric history.
- Search and filtering across typed attributes.
- JSON and OTLP diagnostic bundle export.
- Attribute allowlists and configurable redaction.
- Optional encrypted local persistence.
- Memory and byte budgets in addition to item-count limits.
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
and must not require the main actor. Only presentation belongs on the UI actor.

### Bound resource use

On-device telemetry must not grow without limit. The store should enforce:

- Maximum signal count.
- Maximum estimated bytes.
- Maximum signal age.
- Bounded attribute values.
- Deterministic eviction.

Active or malformed spans must not be retained indefinitely.

### Redact before storage

Sensitive attributes should be rejected or transformed before entering the local
store. Hiding values only in the UI still leaves private data resident in memory
or diagnostic exports.

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

The on-device inspector would answer:

> Where is this operation currently waiting, and what happened on this device?

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

This repository currently captures the project direction. The next milestone is
a small technical spike against OpenTelemetry Swift's span exporter interfaces,
followed by the bounded trace store and first SwiftUI trace tree.
