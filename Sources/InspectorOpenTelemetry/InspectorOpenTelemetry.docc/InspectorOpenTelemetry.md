# ``InspectorOpenTelemetry``

Capture completed OpenTelemetry Swift spans and log records in inspector stores.

## Overview

Create an ``InspectorSpanExporter`` with a core `TraceStore`, then register it
with an OpenTelemetry Swift span processor. Create an ``InspectorLogExporter``
with a core `LogStore`, then register it with a log record processor. Both
exporters convert SDK values into inspector-owned snapshots before storage.

Use OpenTelemetry Swift's `MultiSpanExporter` to send the same completed spans
to the inspector and another backend. A multi-export returns failure if any
child exporter fails, although every child is still invoked.

## Topics

### Exporting

- ``InspectorSpanExporter``
- ``InspectorLogExporter``
