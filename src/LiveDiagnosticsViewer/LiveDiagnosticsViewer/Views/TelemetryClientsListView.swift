import CloudKit
import SwiftUI

struct TelemetryClientsListView: View {
    let clients: [TelemetryClientDisplay]
    let isLoading: Bool
    let isDeletingAll: Bool
    let togglingClientID: CKRecord.ID?
    let toggleClientState: (TelemetryClientDisplay) async -> Void

    var body: some View {
        List(clients) { client in
            TelemetryClientRowView(
                client: client,
                isUpdating: togglingClientID == client.id,
                isDisabled: isLoading || isDeletingAll || togglingClientID == client.id
            ) {
                Task { await toggleClientState(client) }
            }
        }
    }
}
