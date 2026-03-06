import SwiftUI

public struct DiagnosticsView: View {
    private let cloudKitClient: CloudKitClient

    public init(containerIdentifier: String) {
        cloudKitClient = CloudKitClient(containerIdentifier: containerIdentifier)
    }

    public var body: some View {
        ContentView()
            .environment(\.cloudKitClient, cloudKitClient)
            .task { await setupSubscriptions() }
    }

    private func setupSubscriptions() async {
        do {
            if try await cloudKitClient.fetchSubscription(id: "TelemetryClient-All") == nil {
                let id = try await cloudKitClient.createClientRecordSubscription()
                print("📡 [Viewer] Created TelemetryClient subscription: \(id)")
            }
        } catch {
            print("❌ [Viewer] Failed to setup client subscription: \(error)")
        }

        do {
            if try await cloudKitClient.fetchSubscription(id: "TelemetryScenario-All") == nil {
                let id = try await cloudKitClient.createScenarioSubscription()
                print("📡 [Viewer] Created TelemetryScenario subscription: \(id)")
            }
        } catch {
            print("❌ [Viewer] Failed to setup scenario subscription: \(error)")
        }
    }
}
