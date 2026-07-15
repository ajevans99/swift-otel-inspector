# ``InspectorCore``

Store and query bounded, immutable snapshots of completed telemetry.

## Overview

`InspectorCore` has no dependency on OpenTelemetry or SwiftUI. Use
``TraceStore``, ``LogStore``, and ``MetricStore`` apply redaction and resource
limits before telemetry enters memory. Read immutable snapshots directly or
observe bounded store changes through their asynchronous change streams.

## Topics

### Telemetry

- ``SpanSnapshot``
- ``TraceSnapshot``
- ``LogSnapshot``
- ``MetricSnapshot``
- ``MetricSeriesSnapshot``
- ``MetricPointSnapshot``
- ``SpanTreeNode``
- ``TelemetryAttributeValue``

### Storage

- ``TraceStore``
- ``LogStore``
- ``MetricStore``
- ``MetricStoreConfiguration``
- ``MetricStoreStatistics``
- ``TraceStoreConfiguration``
- ``TraceStoreStatistics``
- ``AttributeRedactor``
