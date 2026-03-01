#if os(macOS)
import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI

struct RecordsListMacView: View {
    let telemetryRecords: [TelemetryRecord]
    @Binding var selection: Set<CKRecord.ID>
    @Binding var scenarioFilter: String?
    @Binding var logLevelFilter: TelemetryLogLevel?
    @Binding var sessionIdFilter: String?
    let availableScenarios: [String]
    let availableSessionIds: [String]
    let hasActiveFilters: Bool
    let isLoading: Bool
    let errorMessage: String?
    let fetchRecords: () async -> Void
    let clearRecords: () -> Void
    let isClearing: Bool
    let hasMore: Bool
    let loadMore: () async -> Void
    let isLoadingMore: Bool
    let copySelected: () -> Void
    let copyIsDisabled: Bool
    let recordCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button("Fetch Records", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await fetchRecords() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isClearing || isLoadingMore)

                Button("Copy Selected", systemImage: "doc.on.doc") {
                    copySelected()
                }
                .buttonStyle(.bordered)
                .disabled(copyIsDisabled)
                .keyboardShortcut("c", modifiers: [.command])

                Button(hasActiveFilters ? "Clear Filtered" : "Clear All", systemImage: "trash") {
                    clearRecords()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                .disabled(isLoading || isClearing || isLoadingMore || telemetryRecords.isEmpty)

                if !availableScenarios.isEmpty {
                    Picker("Scenario", selection: $scenarioFilter) {
                        Text("All Scenarios").tag(String?.none)
                        ForEach(availableScenarios, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    }
                    .frame(maxWidth: 200)
                }

                Picker("Log Level", selection: $logLevelFilter) {
                    Text("All Levels").tag(TelemetryLogLevel?.none)
                    ForEach(TelemetryLogLevel.allCases, id: \.rawValue) { level in
                        Text(level.description).tag(TelemetryLogLevel?.some(level))
                    }
                }
                .frame(maxWidth: 160)

                if !availableSessionIds.isEmpty {
                    Picker("Session", selection: $sessionIdFilter) {
                        Text("All Sessions").tag(String?.none)
                        ForEach(availableSessionIds, id: \.self) { id in
                            Text(id).tag(String?.some(id))
                        }
                    }
                    .frame(maxWidth: 200)
                }

                if isLoading || isClearing || isLoadingMore {
                    ProgressView()
                }
            }

            if isLoading {
                ProgressView("Loading records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isClearing {
                ProgressView(hasActiveFilters ? "Clearing filtered records..." : "Clearing all records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if telemetryRecords.isEmpty {
                ContentUnavailableView(
                    "No Records Found",
                    systemImage: "tray",
                    description: Text("Tap 'Fetch Records' to load telemetry data from CloudKit")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 12) {
                    TelemetryTableView(
                        telemetryRecords: telemetryRecords,
                        selection: $selection,
                        copySelected: copySelected
                    )

                    if isLoadingMore {
                        ProgressView("Loading more...")
                    } else if hasMore {
                        Button("Load More Records") {
                            Task {
                                await loadMore()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingMore)
                    }
                }
            }

            if let errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Telemetry Records (\(recordCount))")
        .padding()
    }
}
#endif
