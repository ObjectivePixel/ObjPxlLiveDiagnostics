import CloudKit
import SwiftUI

struct TelemetryClientsListView: View {
    let clients: [TelemetryClientDisplay]
    let isLoading: Bool
    let isDeletingAll: Bool
    let togglingClientID: CKRecord.ID?
    let scenarioCounts: [String: Int]
    let toggleClientState: (TelemetryClientDisplay) async -> Void

    var body: some View {
        List(clients) { client in
            NavigationLink(value: client) {
                TelemetryClientRowView(
                    client: client,
                    isUpdating: togglingClientID == client.id,
                    isDisabled: isLoading || isDeletingAll || togglingClientID == client.id,
                    scenarioCount: scenarioCounts[client.clientId] ?? 0
                ) {
                    Task { await toggleClientState(client) }
                }
            }
        }
    }
}
