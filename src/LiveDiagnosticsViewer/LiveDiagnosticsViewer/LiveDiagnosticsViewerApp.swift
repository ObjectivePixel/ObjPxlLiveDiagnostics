import AppIntents
import ObjPxlLiveTelemetry
import SwiftUI

@main
struct LiveDiagnosticsViewerApp: App {
    private let cloudKitClient: CloudKitClient

    init() {
        cloudKitClient = CloudKitClient(containerIdentifier: TelemetrySchema.cloudKitContainerIdentifierTelemetry)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.cloudKitClient, cloudKitClient)
        }
    }
}
