# ``InspectorOpenTelemetry``

Capture completed OpenTelemetry Swift spans in an inspector store.

## Overview

Create an ``InspectorSpanExporter`` with a core `TraceStore`, then register it
with an OpenTelemetry Swift span processor. The exporter converts SDK
`SpanData` into inspector-owned snapshots before storage.

Use OpenTelemetry Swift's `MultiSpanExporter` to send the same completed spans
to the inspector and another backend. A multi-export returns failure if any
child exporter fails, although every child is still invoked.

## Topics

### Exporting

- ``InspectorSpanExporter``
