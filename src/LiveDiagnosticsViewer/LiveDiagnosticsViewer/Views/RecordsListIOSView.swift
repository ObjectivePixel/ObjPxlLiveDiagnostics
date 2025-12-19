#if os(iOS)
import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI

struct RecordsListIOSView: View {
    let telemetryRecords: [TelemetryRecord]
    @Binding var selection: Set<CKRecord.ID>
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

    var body: some View {
        VStack(alignment: .leading) {
            if isLoading {
                ProgressView("Loading records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isClearing {
                ProgressView("Clearing all records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if telemetryRecords.isEmpty {
                ContentUnavailableView(
                    "No Records Found",
                    systemImage: "tray",
                    description: Text("Tap 'Fetch Records' to load telemetry data from CloudKit")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                TelemetryRecordsListView(
                    telemetryRecords: telemetryRecords,
                    selection: $selection,
                    hasMore: hasMore,
                    loadMore: loadMore,
                    isLoadingMore: isLoadingMore
                )
            }

            if let errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Telemetry Records (\(telemetryRecords.count))")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Fetch Records", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await fetchRecords() }
                }
                .disabled(isLoading || isClearing || isLoadingMore)

                Button("Copy Selected", systemImage: "doc.on.doc") {
                    copySelected()
                }
                .disabled(copyIsDisabled)

                Button("Clear All", systemImage: "trash") {
                    clearRecords()
                }
                .foregroundStyle(.red)
                .disabled(isLoading || isClearing || isLoadingMore || telemetryRecords.isEmpty)
            }
        }
        .padding()
    }
}
#endif
