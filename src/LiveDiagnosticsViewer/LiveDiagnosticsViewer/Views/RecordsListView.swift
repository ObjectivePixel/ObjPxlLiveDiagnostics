import SwiftUI
import CloudKit

struct RecordsListView: View {
    let records: [CKRecord]
    let isLoading: Bool
    let errorMessage: String?
    let fetchRecords: () async -> Void
    let clearRecords: () -> Void
    let isClearing: Bool

    var body: some View {
        VStack {
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
            } else {
                TelemetryTableView(records: records)
            }

            if let errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle("Telemetry Records (\(records.count))")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Clear All") {
                    clearRecords()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                .disabled(isLoading || isClearing || records.isEmpty)

                Button("Fetch Records") {
                    Task {
                        await fetchRecords()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isClearing)
            }
        }
    }
}
