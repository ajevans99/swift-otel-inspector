# ``InspectorSwiftUI``

Browse traces, structured logs, and metrics in embeddable SwiftUI views.

## Overview

Initialize ``TraceInspectorView`` with the same `TraceStore` used by
`InspectorSpanExporter`. The view observes store changes and presents trace
filtering, expandable parent-child trees, errors, attributes, events, links, and
a timeline of correlated logs. Use ``LogInspectorView`` with a `LogStore` for
searchable, severity-aware structured log inspection. Use
``MetricInspectorView`` with a `MetricStore` for Swift Charts histories,
counter rates, reported quantiles, and histogram distributions.

## Topics

### Views

- ``TraceInspectorView``
- ``LogInspectorView``
- ``MetricInspectorView``

### Presentation

- ``TraceInspectorModel``
- ``LogInspectorModel``
- ``MetricInspectorModel``
- ``MetricPresentation``
- ``InspectorFormatting``
