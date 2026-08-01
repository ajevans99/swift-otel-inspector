// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftOTelInspector",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "InspectorCore", targets: ["InspectorCore"]),
        .library(name: "InspectorOpenTelemetry", targets: ["InspectorOpenTelemetry"]),
        .library(name: "InspectorSwiftUI", targets: ["InspectorSwiftUI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/open-telemetry/opentelemetry-swift-core.git",
            exact: "2.5.1"
        ),
    ],
    targets: [
        .target(name: "InspectorCore"),
        .target(
            name: "InspectorOpenTelemetry",
            dependencies: [
                "InspectorCore",
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            ]
        ),
        .target(
            name: "InspectorSwiftUI",
            dependencies: ["InspectorCore"]
        ),
        .testTarget(
            name: "InspectorCoreTests",
            dependencies: ["InspectorCore"]
        ),
        .testTarget(
            name: "InspectorOpenTelemetryTests",
            dependencies: [
                "InspectorCore",
                "InspectorOpenTelemetry",
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            ]
        ),
        .testTarget(
            name: "InspectorSwiftUITests",
            dependencies: ["InspectorCore", "InspectorSwiftUI"]
        ),
    ]
)
