# ``InspectorCore``

Store and query bounded, immutable snapshots of completed telemetry.

## Overview

`InspectorCore` has no dependency on OpenTelemetry or SwiftUI. Use
``TraceStore`` to apply redaction and resource limits before completed spans
enter memory. Read grouped ``TraceSnapshot`` values directly or observe changes
through ``TraceStore/changes()``.

## Topics

### Telemetry

- ``SpanSnapshot``
- ``TraceSnapshot``
- ``SpanTreeNode``
- ``TelemetryAttributeValue``

### Storage

- ``TraceStore``
- ``TraceStoreConfiguration``
- ``TraceStoreStatistics``
- ``AttributeRedactor``
