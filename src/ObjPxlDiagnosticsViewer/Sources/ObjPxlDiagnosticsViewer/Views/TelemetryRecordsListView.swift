import CloudKit
import ObjPxlDiagnosticsShared
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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
                .contextMenu {
                    Button("Copy Session ID", systemImage: "doc.on.doc") {
                        copyToPasteboard(record.sessionId)
                    }
                    Button("Copy Record Name", systemImage: "square.on.square") {
                        copyToPasteboard(record.eventId)
                    }
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

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func toggleSelection(for record: TelemetryRecord) {
        if selection.contains(record.id) {
            selection.remove(record.id)
        } else {
            selection.insert(record.id)
        }
    }
}
