import SwiftUI
import CloudKit

struct RecordCardView: View {
    let record: CKRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record[TelemetrySchema.Field.eventName.rawValue] as? String ?? "Unknown Event")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }

            if let timestamp = record[TelemetrySchema.Field.eventTimestamp.rawValue] as? Date {
                Text(timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let deviceType = record[TelemetrySchema.Field.deviceType.rawValue] as? String {
                    Label(deviceType, systemImage: "devices")
                        .font(.caption)
                }

                if let appVersion = record[TelemetrySchema.Field.appVersion.rawValue] as? String {
                    Label("v\(appVersion)", systemImage: "app.badge")
                        .font(.caption)
                }

                if let osVersion = record[TelemetrySchema.Field.osVersion.rawValue] as? String {
                    Label(osVersion, systemImage: "gear")
                        .font(.caption)
                }
            }

            Text("ID: \(record.recordID.recordName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(.rect(cornerRadius: 12))
    }
}
