# Inspector example app

This native Xcode application target consumes SwiftOTelInspector through its
public products, just as an external application does. Open the repository's
`SwiftOTelInspector.xcworkspace`, select the `InspectorExampleApp` scheme, and
run it on an iOS 17 simulator or device.

The app creates a failed parent-child trace and correlated logs during launch,
exports spans to both the on-device inspector and OpenTelemetry's stdout
exporter, and continuously records metrics. Use it to exercise trace filtering,
the tree, waterfall, timeline, structured log browser, and metric charts.
