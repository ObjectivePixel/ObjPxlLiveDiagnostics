import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI

struct TelemetryTableView: View {
    let telemetryRecords: [TelemetryRecord]
    @Binding var selection: Set<CKRecord.ID>
    let copySelected: () -> Void
    @State private var sortOrder = [KeyPathComparator(\TelemetryRecord.eventTimestamp, order: .reverse)]

    private var sortedRecords: [TelemetryRecord] {
        telemetryRecords.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedRecords, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Timestamp", value: \.eventTimestamp) { record in
                Text(record.formattedTimestamp)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 95, ideal: 120, max: 170)

            TableColumn("Event Name", value: \.eventName) { record in
                Text(record.eventName)
                    .font(.headline)
            }
            .width(min: 120, ideal: 180, max: 300)

            TableColumn("Property 1", value: \.property1) { record in
                Text(record.property1)
                    .font(.body)
                    .help(record.property1)
            }
            .width(min: 200, ideal: 400, max: 800)

            TableColumn("Device Type", value: \.deviceType) { record in
                Label(record.deviceType, systemImage: "devices")
                    .font(.body)
            }
            .width(min: 50, ideal: 65, max: 100)

            TableColumn("App Version", value: \.appVersion) { record in
                Label("v\(record.appVersion)", systemImage: "app.badge")
                    .font(.body)
            }
            .width(min: 40, ideal: 60, max: 90)

            TableColumn("Thread ID", value: \.threadId) { record in
                Text(record.threadId)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 50, max: 75)
        }
        #if os(macOS)
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        #endif
        .contextMenu {
            Button("Copy Selected", systemImage: "doc.on.doc") {
                copySelected()
            }
            .disabled(selection.isEmpty)
        }
    }
}

struct TelemetryRecord: Identifiable {
    let id: CKRecord.ID
    let eventId: String
    let eventName: String
    let eventTimestamp: Date
    let deviceType: String
    let deviceName: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let threadId: String
    let property1: String

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: eventTimestamp)
    }

    init(_ record: CKRecord) {
        id = record.recordID
        eventId = record.recordID.recordName
        eventName = record[TelemetrySchema.Field.eventName.rawValue] as? String ?? "Unknown"
        eventTimestamp = record[TelemetrySchema.Field.eventTimestamp.rawValue] as? Date ?? Date()
        deviceType = record[TelemetrySchema.Field.deviceType.rawValue] as? String ?? "N/A"
        deviceName = record[TelemetrySchema.Field.deviceName.rawValue] as? String ?? "N/A"
        deviceModel = record[TelemetrySchema.Field.deviceModel.rawValue] as? String ?? "N/A"
        osVersion = record[TelemetrySchema.Field.osVersion.rawValue] as? String ?? "N/A"
        appVersion = record[TelemetrySchema.Field.appVersion.rawValue] as? String ?? "N/A"
        threadId = record[TelemetrySchema.Field.threadId.rawValue] as? String ?? "N/A"
        property1 = record[TelemetrySchema.Field.property1.rawValue] as? String ?? "N/A"
    }
}
