import CloudKit
import SwiftUI

struct TelemetryRecordsListView: View {
    let telemetryRecords: [TelemetryRecord]
    @Binding var selection: Set<CKRecord.ID>
    let hasMore: Bool
    let loadMore: () async -> Void
    let isLoadingMore: Bool

    var body: some View {
        List {
            ForEach(telemetryRecords) { record in
                TelemetryRecordRowView(
                    record: record,
                    isSelected: selection.contains(record.id)
                ) {
                    toggleSelection(for: record)
                }
            }

            if isLoadingMore {
                ProgressView("Loading more...")
            } else if hasMore {
                Button("Load More Records") {
                    Task {
                        await loadMore()
                    }
                }
                .disabled(isLoadingMore)
            }
        }
    }

    private func toggleSelection(for record: TelemetryRecord) {
        if selection.contains(record.id) {
            selection.remove(record.id)
        } else {
            selection.insert(record.id)
        }
    }
}
