// swift-tools-version: 5.9
import PackageDescription

// Standalone package for viewer library usage.
// Preferred build: use the root Package.swift (swift build from repo root).
// This package relies on local symlinks (SharedCloudKit, SharedTypes) that
// point to src/SharedCloudKit and src/SharedTypes.

let package = Package(
    name: "ObjPxlDiagnosticsViewer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .visionOS(.v1),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "ObjPxlDiagnosticsViewer",
            targets: ["ObjPxlDiagnosticsViewer"]
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
            name: "ObjPxlDiagnosticsViewer",
            dependencies: ["ObjPxlDiagnosticsShared"],
            path: "Sources/ObjPxlDiagnosticsViewer"
        ),
        .testTarget(
            name: "ObjPxlDiagnosticsViewerTests",
            dependencies: ["ObjPxlDiagnosticsViewer", "ObjPxlDiagnosticsShared"],
            path: "Tests/ObjPxlDiagnosticsViewerTests"
        )
    ]
)
