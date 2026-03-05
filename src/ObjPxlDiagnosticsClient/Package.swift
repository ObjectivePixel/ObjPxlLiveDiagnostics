// swift-tools-version: 5.9
import PackageDescription

// Standalone package for client library usage.
// Preferred build: use the root Package.swift (swift build from repo root).
// This package relies on local symlinks (SharedCloudKit, SharedTypes) that
// point to src/SharedCloudKit and src/SharedTypes.

let package = Package(
    name: "ObjPxlDiagnosticsClient",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .visionOS(.v1),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "ObjPxlLiveTelemetry",
            targets: ["ObjPxlLiveTelemetry"]
        )
    ],
    targets: [
        .target(
            name: "ObjPxlDiagnosticsShared",
            path: ".",
            sources: [
                "SharedCloudKit",
                "SharedTypes"
            ]
        ),
        .target(
            name: "ObjPxlLiveTelemetry",
            dependencies: ["ObjPxlDiagnosticsShared"],
            path: "Sources/ObjPxlLiveTelemetry"
        ),
        .testTarget(
            name: "ObjPxlLiveTelemetryTests",
            dependencies: ["ObjPxlLiveTelemetry"],
            path: "Tests/ObjPxlLiveTelemetryTests"
        )
    ]
)
