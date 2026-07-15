# Inspector example app

This standalone Swift package consumes SwiftOTelInspector through its public
products, just as an external application does. Open this directory's
`Package.swift` in Xcode, select the `InspectorExampleApp` scheme, and run it on
an iOS 17 simulator or macOS.

The app creates a failed parent-child trace during launch and exports it to both
the on-device inspector and OpenTelemetry's stdout exporter. Use it to exercise
trace filtering, the tree, the waterfall, and span details.
