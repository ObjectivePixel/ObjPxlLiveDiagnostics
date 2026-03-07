import SwiftUI
import ObjPxlDiagnosticsShared

struct TelemetryClientsHeaderView: View {
    @Binding var filter: ClientFilter
    let isLoading: Bool
    let isDeletingAll: Bool
    let clients: [TelemetryClientDisplay]
    let fetchClients: () async -> Void
    let requestDeleteAll: () -> Void
    let requestAddClient: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(ClientFilter.allCases) { option in
                    Text(option.rawValue)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Button("Add Client", systemImage: "plus") {
                requestAddClient()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || isDeletingAll)

            Button("Fetch Clients", systemImage: "arrow.triangle.2.circlepath") {
                Task { await fetchClients() }
            }
            .buttonStyle(.bordered)
            .disabled(isLoading || isDeletingAll)

            Button("Deactivate All", systemImage: "stop.circle") {
                requestDeleteAll()
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)
            .disabled(isLoading || isDeletingAll || clients.isEmpty)

            if isLoading || isDeletingAll {
                ProgressView()
                    .padding(.leading, 8)
            }
        }
    }
}
