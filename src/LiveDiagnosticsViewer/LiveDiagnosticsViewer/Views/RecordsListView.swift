import SwiftUI
import CloudKit
import ObjPxlLiveTelemetry
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RecordsListView: View {
    let records: [CKRecord]
    let isLoading: Bool
    let errorMessage: String?
    let fetchRecords: () async -> Void
    let clearRecords: () -> Void
    let isClearing: Bool
    let hasMore: Bool
    let loadMore: () async -> Void
    let isLoadingMore: Bool
    @State private var selection = Set<CKRecord.ID>()

    private var telemetryRecords: [TelemetryRecord] {
        records.map(TelemetryRecord.init)
    }

    private var selectedTelemetryRecords: [TelemetryRecord] {
        telemetryRecords.filter { selection.contains($0.id) }
    }

    private var copyIsDisabled: Bool {
        selectedTelemetryRecords.isEmpty || isLoading || isClearing || isLoadingMore
    }

    private func copySelected() {
        guard !selectedTelemetryRecords.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        let header = [
            "recordID",
            "eventName",
            "eventTimestamp",
            "deviceType",
            "deviceName",
            "deviceModel",
            "osVersion",
            "appVersion",
            "threadId",
            "property1"
        ].joined(separator: ",")

        func escape(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        let rows = selectedTelemetryRecords.map { record in
            [
                record.eventId,
                record.eventName,
                formatter.string(from: record.eventTimestamp),
                record.deviceType,
                record.deviceName,
                record.deviceModel,
                record.osVersion,
                record.appVersion,
                record.threadId,
                record.property1
            ]
            .map(escape)
            .joined(separator: ",")
        }

        let csv = ([header] + rows).joined(separator: "\n")

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
        #else
        UIPasteboard.general.string = csv
        #endif
    }

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
                #if os(macOS)
                .keyboardShortcut("c", modifiers: [.command])
                #endif

                Button("Clear All", systemImage: "trash") {
                    clearRecords()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                .disabled(isLoading || isClearing || isLoadingMore || records.isEmpty)

                if isLoading || isClearing || isLoadingMore {
                    ProgressView()
                }
            }

            if isLoading {
                ProgressView("Loading records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isClearing {
                ProgressView("Clearing all records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
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
        .navigationTitle("Telemetry Records (\(records.count))")
        .padding()
    }
}
