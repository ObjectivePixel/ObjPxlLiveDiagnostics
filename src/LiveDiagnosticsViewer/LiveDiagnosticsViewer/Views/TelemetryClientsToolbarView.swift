#if os(iOS)
import SwiftUI

struct TelemetryClientsToolbarView: ToolbarContent {
    let isLoading: Bool
    let isDeletingAll: Bool
    let clients: [TelemetryClientDisplay]
    let fetchClients: () async -> Void
    let requestDeleteAll: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Fetch Clients", systemImage: "arrow.triangle.2.circlepath") {
                Task { await fetchClients() }
            }
            .disabled(isLoading || isDeletingAll)

            Button("Delete All", systemImage: "trash") {
                requestDeleteAll()
            }
            .foregroundStyle(.red)
            .disabled(isLoading || isDeletingAll || clients.isEmpty)
        }
    }
}
#endif
