#if os(iOS)
import SwiftUI

struct TelemetryClientsToolbarView: ToolbarContent {
    let isLoading: Bool
    let isDeletingAll: Bool
    let clients: [TelemetryClientDisplay]
    let fetchClients: () async -> Void
    let requestDeleteAll: () -> Void
    let requestAddClient: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add Client", systemImage: "plus") {
                requestAddClient()
            }
            .disabled(isLoading || isDeletingAll)
        }

        ToolbarItemGroup(placement: .bottomBar) {
            Button("Fetch Clients", systemImage: "arrow.triangle.2.circlepath") {
                Task { await fetchClients() }
            }
            .disabled(isLoading || isDeletingAll)

            Button("Deactivate All", systemImage: "stop.circle") {
                requestDeleteAll()
            }
            .foregroundStyle(.red)
            .disabled(isLoading || isDeletingAll || clients.isEmpty)
        }
    }
}
#endif
