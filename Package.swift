// swift-tools-version: 6.0

import PackageDescription

#if TUIST
let documentationCatalogResourceSuffix = "/**"
#else
let documentationCatalogResourceSuffix = ""
#endif

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
        .target(
            name: "InspectorCore",
            resources: [.copy("InspectorCore.docc\(documentationCatalogResourceSuffix)")]
        ),
        .target(
            name: "InspectorOpenTelemetry",
            dependencies: [
                "InspectorCore",
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            ],
            resources: [
                .copy("InspectorOpenTelemetry.docc\(documentationCatalogResourceSuffix)")
            ]
        ),
        .target(
            name: "InspectorSwiftUI",
            dependencies: ["InspectorCore"],
            resources: [.copy("InspectorSwiftUI.docc\(documentationCatalogResourceSuffix)")]
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
