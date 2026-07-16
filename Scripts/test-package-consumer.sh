#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/swift-otel-consumer.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT

mkdir -p "$temporary_directory/Sources/Consumer"

cat > "$temporary_directory/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Consumer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "SwiftOTelInspector", path: "$repo_root")],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [
                .product(name: "InspectorCore", package: "SwiftOTelInspector"),
                .product(name: "InspectorOpenTelemetry", package: "SwiftOTelInspector"),
                .product(name: "InspectorSwiftUI", package: "SwiftOTelInspector"),
            ]
        ),
    ]
)
EOF

cat > "$temporary_directory/Sources/Consumer/main.swift" <<'EOF'
import InspectorCore
import InspectorOpenTelemetry
import InspectorSwiftUI

let store = TraceStore()
_ = InspectorSpanExporter(store: store)
_ = TraceInspectorView(store: store)
print(InspectorCore.version)
EOF

swift build --package-path "$temporary_directory"
