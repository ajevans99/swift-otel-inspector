// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InspectorExampleApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .executable(name: "InspectorExampleApp", targets: ["InspectorExampleApp"]),
    ],
    dependencies: [
        .package(name: "SwiftOTelInspector", path: "../.."),
        .package(
            url: "https://github.com/open-telemetry/opentelemetry-swift-core.git",
            exact: "2.5.1"
        ),
    ],
    targets: [
        .executableTarget(
            name: "InspectorExampleApp",
            dependencies: [
                .product(name: "InspectorCore", package: "SwiftOTelInspector"),
                .product(name: "InspectorOpenTelemetry", package: "SwiftOTelInspector"),
                .product(name: "InspectorSwiftUI", package: "SwiftOTelInspector"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
                .product(name: "StdoutExporter", package: "opentelemetry-swift-core"),
            ]
        ),
    ]
)
