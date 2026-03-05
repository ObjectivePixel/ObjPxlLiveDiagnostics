import CloudKit
import SwiftUI

struct DetailView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    let selectedAction: SidebarAction?
    let records: [CKRecord]
    let isLoading: Bool
    let errorMessage: String?
    let fetchRecords: () async -> Void
    let clearRecords: () -> Void
    let isClearing: Bool
    let hasMore: Bool
    let loadMore: () async -> Void
    let isLoadingMore: Bool
    @Binding var scenarioFilter: String?
    @Binding var logLevelFilter: TelemetryLogLevel?
    @Binding var sessionIdFilter: String?
    let availableScenarios: [String]
    let availableSessionIds: [String]
    @Binding var showClearConfirmation: Bool
    let hasActiveFilters: Bool

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
                    isClearing: isClearing,
                    hasMore: hasMore,
                    loadMore: loadMore,
                    isLoadingMore: isLoadingMore,
                    scenarioFilter: $scenarioFilter,
                    logLevelFilter: $logLevelFilter,
                    sessionIdFilter: $sessionIdFilter,
                    availableScenarios: availableScenarios,
                    availableSessionIds: availableSessionIds,
                    hasActiveFilters: hasActiveFilters
                )
            case .scenarios:
                ScenariosView()
            case .schema:
                SchemaView()
            case .debug:
                DebugInfoView()
            case .clients:
                TelemetryClientsView()
            case .admin:
                AdminDeleteView()
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
