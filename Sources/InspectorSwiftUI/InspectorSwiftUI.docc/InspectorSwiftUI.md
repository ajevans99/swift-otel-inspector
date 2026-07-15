# ``InspectorSwiftUI``

Browse completed traces, span details, and structured logs in embeddable SwiftUI views.

## Overview

Initialize ``TraceInspectorView`` with the same `TraceStore` used by
`InspectorSpanExporter`. The view observes store changes and presents trace
filtering, expandable parent-child trees, errors, attributes, events, links, and
a timeline of correlated logs. Use ``LogInspectorView`` with a `LogStore` for
searchable, severity-aware structured log inspection.

## Topics

### Views

- ``TraceInspectorView``
- ``LogInspectorView``

### Presentation

- ``TraceInspectorModel``
- ``LogInspectorModel``
- ``InspectorFormatting``
