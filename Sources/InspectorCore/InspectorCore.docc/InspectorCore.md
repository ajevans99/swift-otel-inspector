# ``InspectorCore``

Store and query bounded, immutable snapshots of completed telemetry.

## Overview

`InspectorCore` has no dependency on OpenTelemetry or SwiftUI. Use
``TraceStore`` and ``LogStore`` to apply redaction and resource limits before
telemetry enters memory. Read snapshots directly or observe bounded store
changes through their asynchronous change streams.

## Topics

### Telemetry

- ``SpanSnapshot``
- ``TraceSnapshot``
- ``LogSnapshot``
- ``SpanTreeNode``
- ``TelemetryAttributeValue``

### Storage

- ``TraceStore``
- ``LogStore``
- ``TraceStoreConfiguration``
- ``TraceStoreStatistics``
- ``AttributeRedactor``
