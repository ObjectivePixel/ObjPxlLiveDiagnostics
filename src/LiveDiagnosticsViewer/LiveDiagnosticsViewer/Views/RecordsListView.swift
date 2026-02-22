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
    @Binding var scenarioFilter: String?
    @Binding var logLevelFilter: String?
    let availableScenarios: [String]
    @State private var selection = Set<CKRecord.ID>()

    private var telemetryRecords: [TelemetryRecord] {
        records.map(TelemetryRecord.init)
    }

    /// Filters telemetry records by scenario name. Returns all records when filter is nil.
    static func filterRecords(_ records: [TelemetryRecord], byScenario scenario: String?) -> [TelemetryRecord] {
        guard let scenario else { return records }
        return records.filter { $0.scenario == scenario }
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
            "scenario",
            "logLevel",
            "deviceType",
            "deviceName",
            "deviceModel",
            "osVersion",
            "appVersion",
            "threadId",
            "property1"
        ].joined(separator: ",")

        func escape(_ value: String) -> String {
            "\"\(value.replacing("\"", with: "\"\""))\""
        }

        let rows = selectedTelemetryRecords.map { record in
            [
                record.eventId,
                record.eventName,
                formatter.string(from: record.eventTimestamp),
                record.scenario ?? "",
                record.logLevel ?? "",
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
        #if os(iOS)
        RecordsListIOSView(
            telemetryRecords: telemetryRecords,
            selection: $selection,
            scenarioFilter: $scenarioFilter,
            logLevelFilter: $logLevelFilter,
            availableScenarios: availableScenarios,
            isLoading: isLoading,
            errorMessage: errorMessage,
            fetchRecords: fetchRecords,
            clearRecords: clearRecords,
            isClearing: isClearing,
            hasMore: hasMore,
            loadMore: loadMore,
            isLoadingMore: isLoadingMore,
            copySelected: copySelected,
            copyIsDisabled: copyIsDisabled
        )
        #else
        RecordsListMacView(
            telemetryRecords: telemetryRecords,
            selection: $selection,
            scenarioFilter: $scenarioFilter,
            logLevelFilter: $logLevelFilter,
            availableScenarios: availableScenarios,
            isLoading: isLoading,
            errorMessage: errorMessage,
            fetchRecords: fetchRecords,
            clearRecords: clearRecords,
            isClearing: isClearing,
            hasMore: hasMore,
            loadMore: loadMore,
            isLoadingMore: isLoadingMore,
            copySelected: copySelected,
            copyIsDisabled: copyIsDisabled,
            recordCount: records.count
        )
        #endif
    }
}
