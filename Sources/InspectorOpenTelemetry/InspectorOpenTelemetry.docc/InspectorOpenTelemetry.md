# ``InspectorOpenTelemetry``

Capture OpenTelemetry Swift spans, logs, and metrics in inspector stores.

## Overview

Create one ``InspectorTelemetry`` value to retain a matching set of bounded
trace, log, and metric stores. Call `makeExporters()` once for each independently
owned runtime pipeline, and use the same stores to initialize the SwiftUI views.
Each ``InspectorExporterSet`` shares the retained stores but has an independent,
terminal shutdown lifecycle.

Alternatively, create an ``InspectorSpanExporter`` with a core `TraceStore`,
then register it with an OpenTelemetry Swift span processor. Create an
``InspectorLogExporter`` with a core `LogStore`, then register it with a log
record processor. Both exporters convert SDK values into inspector-owned
snapshots before storage.

Create an ``InspectorMetricExporter`` with a core `MetricStore`, then use it
with `PeriodicMetricReaderBuilder`. Register separate readers for local and
remote metric export so each destination retains independent collection and
lifecycle behavior.

Use OpenTelemetry Swift's `MultiSpanExporter` to send the same completed spans
to the inspector and another backend. A multi-export returns failure if any
child exporter fails, although every child is still invoked.

## Topics

### Exporting

- ``InspectorTelemetry``
- ``InspectorExporterSet``
- ``InspectorSpanExporter``
- ``InspectorLogExporter``
- ``InspectorMetricExporter``
