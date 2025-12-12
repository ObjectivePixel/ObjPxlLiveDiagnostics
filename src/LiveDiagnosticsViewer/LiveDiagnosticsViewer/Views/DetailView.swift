import SwiftUI
import CloudKit

struct DetailView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    let selectedAction: SidebarAction?
    let records: [CKRecord]
    let isLoading: Bool
    let errorMessage: String?
    let fetchRecords: () async -> Void
    let clearRecords: () -> Void
    let isClearing: Bool
    @Binding var showClearConfirmation: Bool

    var body: some View {
        Group {
            switch selectedAction {
            case .records:
                RecordsListView(
                    records: records,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    fetchRecords: fetchRecords,
                    clearRecords: clearRecords,
                    isClearing: isClearing
                )
            case .schema:
                SchemaView()
            case .debug:
                DebugInfoView()
            case .clients:
                TelemetryClientsView()
            case .none:
                ContentUnavailableView(
                    "Select a Tool",
                    systemImage: "sidebar.left",
                    description: Text("Choose an option from the sidebar to get started")
                )
            }
        }
    }
}
