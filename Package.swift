// swift-tools-version: 5.9
import PackageDescription

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
        ),
        .library(
            name: "ObjPxlDiagnosticsViewer",
            targets: ["ObjPxlDiagnosticsViewer"]
        ),
    ],
    targets: [
        .target(
            name: "ObjPxlDiagnosticsShared",
            path: "src",
            sources: [
                "SharedCloudKit",
                "SharedTypes"
            ]
        ),
        .target(
            name: "ObjPxlLiveTelemetry",
            dependencies: ["ObjPxlDiagnosticsShared"],
            path: "src/ObjPxlDiagnosticsClient/Sources/ObjPxlLiveTelemetry"
        ),
        .testTarget(
            name: "ObjPxlLiveTelemetryTests",
            dependencies: ["ObjPxlLiveTelemetry"],
            path: "src/ObjPxlDiagnosticsClient/Tests/ObjPxlLiveTelemetryTests"
        ),
        .target(
            name: "ObjPxlDiagnosticsViewer",
            dependencies: ["ObjPxlDiagnosticsShared"],
            path: "src/ObjPxlDiagnosticsViewer/Sources/ObjPxlDiagnosticsViewer"
        ),
        .testTarget(
            name: "ObjPxlDiagnosticsViewerTests",
            dependencies: ["ObjPxlDiagnosticsViewer"],
            path: "src/ObjPxlDiagnosticsViewer/Tests/ObjPxlDiagnosticsViewerTests"
        ),
    ]
)
