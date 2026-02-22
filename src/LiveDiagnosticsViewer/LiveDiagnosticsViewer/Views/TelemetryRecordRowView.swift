import SwiftUI

struct TelemetryRecordRowView: View {
    let record: TelemetryRecord
    let isSelected: Bool
    let toggleSelection: () -> Void

    var body: some View {
        Button(action: toggleSelection) {
            HStack {
                VStack(alignment: .leading) {
                    Text(record.eventName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(record.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(record.property1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let scenario = record.scenario, !scenario.isEmpty {
                            Label(scenario, systemImage: "tag")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }

                        if let logLevel = record.logLevel, !logLevel.isEmpty {
                            Text(logLevel.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(logLevel == "diagnostic" ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                                .clipShape(.rect(cornerRadius: 4))
                        }
                    }

                    HStack {
                        Label(record.deviceType, systemImage: "devices")
                        Label("v\(record.appVersion)", systemImage: "app.badge")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
