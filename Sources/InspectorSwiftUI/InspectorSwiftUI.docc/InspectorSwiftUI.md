# ``InspectorSwiftUI``

Browse completed traces and span details in an embeddable SwiftUI view.

## Overview

Initialize ``TraceInspectorView`` with the same `TraceStore` used by
`InspectorSpanExporter`. The view observes store changes and presents trace
filtering, expandable parent-child trees, errors, attributes, events, and links.

## Topics

### Views

- ``TraceInspectorView``

### Presentation

- ``TraceInspectorModel``
- ``InspectorFormatting``
