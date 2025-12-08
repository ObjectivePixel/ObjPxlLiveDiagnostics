import SwiftUI
import ObjPxlLiveTelemetry

@main
struct LiveDiagnosticsViewerApp: App {
    private let cloudKitClient: CloudKitClient

    init() {
        cloudKitClient = CloudKitClient(containerIdentifier: "iCloud.objpxl.example.telemetry")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.cloudKitClient, cloudKitClient)
        }
    }
}
