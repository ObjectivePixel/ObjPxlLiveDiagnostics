import AppIntents
import ObjPxlLiveTelemetry
import SwiftUI

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
